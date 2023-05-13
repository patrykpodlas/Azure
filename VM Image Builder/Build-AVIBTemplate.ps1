<#
.SYNOPSIS
    Replaces the necessary parameters in the .JSON template file, ready for submission using the Build-AVIBImage function.
.EXAMPLE
    Build-AVIBTemplate `
        -TemplateFilePath "/Azure/VM Image Builder/image_templates/windows_11_gen2_generic.json" `
        -SubscriptionID "" ` # Provide your Azure Subscription ID.
        -ImageResourceGroup "rg-vmimagebuilder" `
        -StagingImageResourceGroup "rg-vmimagebuilder-staging" `
        -Location "uksouth" `
        -ImageDefinitionName "windows_11_gen2_generic" `
        -vNETName "vnet-vmimagebuilder" `
        -SubnetName "snet-vnet-vmimagebuilder" `
        -vNetResourceGroup "rg-vmimagebuilder" `
        -UserManagedIdentityName "umi-vmimagebuilder" `
        -GalleryName "cgvmibimages" `
        -RunOutputName "windows_11_gen2_generic"
.NOTES
    Author: Patryk Podlas
    Created: 13/05/2023

    Change history:
    Date            Author      V       Notes
    13/05/2023      PP          1.0     First release
#>
function Build-AVIBTemplate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TemplateFilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubscriptionID,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ImageResourceGroup,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StagingImageResourceGroup,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ImageDefinitionName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$vNETName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubnetName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$vNetResourceGroup,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UserManagedIdentityName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$GalleryName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RunOutputName
    )

    begin {
        Write-Verbose "Creating new directory for image definition."
        New-Item -Path $ImageDefinitionName -ItemType Directory -Force

        Write-Verbose "Copying template file to new directory"
        $DestinationPath = Join-Path -Path $ImageDefinitionName -ChildPath "$ImageDefinitionName.json"
        Copy-Item -LiteralPath $TemplateFilePath -Destination $DestinationPath

        Write-Verbose "Performing replacements in copied template."

        $Replacements = @{
            '<SubscriptionID>'            = $SubscriptionID
            '<ImageResourceGroup>'        = $ImageResourceGroup
            '<StagingImageResourceGroup>' = $StagingImageResourceGroup
            '<Location>'                  = $Location
            '<ImageDefinitionName>'       = $ImageDefinitionName
            '<vNETName>'                  = $vNETName
            '<SubnetName>'                = $SubnetName
            '<vNetResourceGroup>'         = $vNetResourceGroup
            '<UserManagedIdentityName>'   = $UserManagedIdentityName
            '<GalleryName>'               = $GalleryName
            '<RunOutputName>'             = $RunOutputName
        }

        $Content = Get-Content -LiteralPath $DestinationPath -Raw

        foreach ($Key in $Replacements.Keys) {
            $Content = $Content -replace $Key, $Replacements[$Key]
        }

        Write-Verbose "Saving updated template."
        Set-Content -LiteralPath $DestinationPath -Value $Content
    }
}
