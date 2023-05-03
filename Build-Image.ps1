<#
.SYNOPSIS
    Submits the template to Azure VM Image Builder and initiates build operation.
.DESCRIPTION
    Submits the template to Azure VM Image Builder and initiates build operation. This function will automatically submit the template for build, with appropriate version number specified through the buildversion parameter.
    It also checks for any existing template submissions that are in progress, which will prevent new builds if using a staging resource group.
    A simple while statement keeps track of the progress, the entire process takes over an hour.
    Checks for success of the build at the end.
    The templates can't be updated, each time a unique template name must be submitted, removing a previous template will free up this name.
    API version used: 2022-02-14, for a list of available API's visit: https://learn.microsoft.com/en-us/azure/templates/microsoft.virtualmachineimages/2022-02-14/imagetemplates?pivots=deployment-language-arm-template#arm-template-resource-definition
.PARAMETER BuildVersion
    Specify the build version, which will get passed onto the .JSON file, this ensures no random version by Azure is selected, I suggest using format of 1.0.1 as an example.
    The version must be unique each time a template is submitted.
.PARAMETER Location
    Location where the template is to be submitted to, such as uksouth.
.PARAMETER ImageResourceGroup
    Resource group where the template is going to be placed in, this group should contain all of your core AVIB resources.
.PARAMETER TemplateFilePath
    Path to the .JSON template. This will be appended with the specified $BuildVersion, example: "windows_11_gen2_integration_developer_v" + 1.0.0 will equal to windows_11_gen2_integration_developer_v1.0.0.
    I suggest editing the parameter value to hard-code the first part of the name. This function can be re-used with multiple builds for different purposes.
.PARAMETER ImageTemplateName
    Unique name of the template that will be submitted.
.PARAMETER ImageStagingResourceGroup
    Name of the staging resource group where the temporary resources will be placed.
.EXAMPLE
    PS C:\> Build-Image -BuildVersion "1.0.1" -Location uksouth -ImageResourceGroup rg-developer-vmimagebuilder -TemplateFilePath ".\windows_11_gen2_integration_developer.json" -ImageStagingResourceGroup rg-developer-vmimagebuilder-staging
    Explanation of what the example does
.NOTES
    Author: Patryk Podlas
    Created: 20/04/2023

    Change history:
    Date            Author      V       Notes
    20/04/2023      PP          1.0     First release
#>

function Build-Image {
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [string]$BuildVersion,
        [parameter(Mandatory)]
        [string]$Location,
        [parameter(Mandatory)]
        [string]$ImageResourceGroup,
        [parameter(Mandatory)]
        [string]$TemplateFilePath,
        [string]$ImageTemplateName = "windows_11_gen2_integration_developer_v" + $($BuildVersion),
        [parameter(Mandatory)]
        [string]$ImageStagingResourceGroup
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
            if (Get-AzStorageAccount -ResourceGroupName $ImageStagingResourceGroup) {
                Write-Output "Temporary storage account is present in the resource group for troubleshooting purposes, are you sure you want to delete it?"
                Get-AzStorageAccount -ResourceGroupName $ImageStagingResourceGroup | Remove-AzStorageAccount
            }
        }
    }
    process {
        New-AzResourceGroupDeployment `
            -ResourceGroupName $ImageResourceGroup `
            -TemplateFile $TemplateFilePath `
            -TemplateParameterObject @{"api-Version" = $($APIVersion) ; "buildversion" = $($BuildVersion) } `
            -imageTemplateName $ImageTemplateName `
            -svclocation $Location

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