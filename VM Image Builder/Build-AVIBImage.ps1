<#
.SYNOPSIS
    Submits the template to Azure VM Image Builder and initiates build operation.
.DESCRIPTION
    Submits the template to Azure VM Image Builder and initiates build operation. This function will automatically submit the template for build, with appropriate version number specified through the BuildVersion parameter.
    It also checks for any existing template submissions that are in progress, which will prevent new builds if using a staging resource group, because it has to be empty.
    A simple while statement keeps track of the progress, the entire process takes around 70 minutes.
    Checks for success of the build at the end.
    The templates can't be updated, each time a unique template name must be submitted, removing a previous template will free up this name.
    API version used: 2022-02-14, for a list of available API's visit: https://learn.microsoft.com/en-us/azure/templates/microsoft.virtualmachineimages/2022-02-14/imagetemplates?pivots=deployment-language-arm-template#arm-template-resource-definition
.PARAMETER BuildVersion
    Specify the build version, which will get passed onto the .JSON file, this ensures no random version by Azure is chosen, I suggest using format of 1.0.1 as an example.
    The version must be unique each time a template is submitted.
.PARAMETER ImageResourceGroup
    Resource group where the template is going to be placed in, this group should contain all of your core AVIB resources.
.PARAMETER StagingImageResourceGroup
    Name of the staging resource group where the temporary resources will be created by the service.
.PARAMETER TemplateFilePath
    Path to the .JSON template. This will be appended with the specified $BuildVersion, example: "windows_11_gen2_generic_v" + 1.0.0 will equal to windows_11_gen2_generic_v1.0.0.
    I suggest editing the parameter value to hard-code the first part of the name. This function can be re-used with multiple builds for different purposes.
.PARAMETER ImageTemplateName
    Unique name of the template that will be submitted.
    When running the function, replace the prefix of the template, it will then get concatenated with the version number entered.
    This parameter must not be specified when running.
.EXAMPLE
    Build-AVIBImage `
        -BuildVersion "1.0.2" `
        -ImageResourceGroup "rg-vmimagebuilder" `
        -StagingImageResourceGroup "rg-vmimagebuilder-staging" `
        -TemplateFilePath "./windows_11_gen2_generic/windows_11_gen2_generic.json"
.NOTES
    Author: Patryk Podlas
    Created: 20/04/2023

    Change history:
    Date            Author      V       Notes
    20/04/2023      PP          1.0     First release
    13/05/2023      PP          1.1     Few minor changes, removed the svclocation parameter as it was redundant.
#>

function Build-AVIBImage {
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BuildVersion,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ImageResourceGroup,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$StagingImageResourceGroup,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TemplateFilePath, # Use the previously generated template path.
        [ValidateNotNullOrEmpty()]
        [string]$ImageTemplateName = "windows_11_gen2_generic_v" + $($BuildVersion) # This will be a parameter passed onto the .JSON file, and become the name of the template submitted to Azure VM Image Builder.

    )

    begin {
        $APIVersion = "2022-02-14" # For a list of available API's visit: https://learn.microsoft.com/en-us/azure/templates/microsoft.virtualmachineimages/2022-02-14/imagetemplates?pivots=deployment-language-arm-template#arm-template-resource-definition
        [int]$Time = "0"
        # Check for existing template submissions.
        $CurrentSubmissions = Get-AzImageBuilderTemplate -ResourceGroupName $ImageResourceGroup
        $ListOfStatuses = @(
            "Running"
            "Canceling"
            "Creating"
        )
        # Check if any of them are running, if so - this is going to prevent the build since the staging group needs to be empty to start a new deployment.
        foreach ($Submission in $CurrentSubmissions) {
            $CurrentState = $Submission.LastRunStatusRunState
            if ($CurrentState -in $ListOfStatuses) {
                Write-Output "The state of job: $($Submission.Name) prevents the build from continuation."
                Exit
            }
        }
        # Check if the about to be submitted template name already exists, which is unsupported.
        if ($CurrentSubmissions | Where-Object Name -eq $ImageTemplateName) {
            Write-Output "The template $($ImageTemplateName) already exists, this action is unsupported. Change the submitted template name or delete existing and re-try."
            Exit
        }
        # Check for storage account existance in the resource group and delete it if present.
        if ($CurrentSubmissions.LastRunStatusRunState -notin $ListOfStatuses) {
            if (Get-AzStorageAccount -ResourceGroupName $StagingImageResourceGroup) {
                Write-Output "Temporary storage account is present in the resource group for troubleshooting purposes, are you sure you want to delete it?"
                Get-AzStorageAccount -ResourceGroupName $StagingImageResourceGroup | Remove-AzStorageAccount
            }
        }
    }
    process {
        New-AzResourceGroupDeployment `
            -ResourceGroupName $ImageResourceGroup `
            -TemplateFile $TemplateFilePath `
            -TemplateParameterObject @{"api-Version" = $($APIVersion) ; "buildversion" = $($BuildVersion) } `
            -imageTemplateName $ImageTemplateName `

        Start-AzImageBuilderTemplate `
            -ResourceGroupName $ImageResourceGroup `
            -Name $ImageTemplateName `
            -NoWait

        while ((Get-AzImageBuilderTemplate -ImageTemplateName $ImageTemplateName -ResourceGroupName $ImageResourceGroup | Select-Object -Property Name, LastRunStatusRunState, LastRunStatusMessage, ProvisioningState).LastRunStatusRunState -eq "Running") {
            Start-Sleep -Seconds 60
            Write-Output "$(Get-Date): Image creation is in progress, total time: $($Time/60) minute(s)."
            [int]$Time += "60"
        }
    }

    end {
        $EndState = (Get-AzImageBuilderTemplate -ImageTemplateName $ImageTemplateName -ResourceGroupName $ImageResourceGroup | Select-Object -Property Name, LastRunStatusRunState, LastRunStatusMessage, ProvisioningState).LastRunStatusRunState
        if ($EndState -eq "Succeeded") {
            # Add delete storage account since no troubleshooting is necessary.
            Write-Output "Build has been successful."
        } elseif ($EndState -eq "Failed") {
            Write-Output "Build has failed."
        } elseif ($EndState -eq "Canceled") {
            Write-Output "Build has been cancelled."
        }
    }
}