<#
.SYNOPSIS
    Builds the environment for Azure VM Image Builder.
.DESCRIPTION
    Builds the environment for Azure VM Image Builder. This function, builds the entire environment using best practises.
        - Uses a staging group
        - Uses private networking
    - Registers the required providers.
    - Configures a new vNET and NSG, as well as the required security rule configuration, sets the privateLinkServiceNetworkPolicies to disabled.
    - Creates Azure Compute Gallery and Image Definition (Gen2)
    - Uses .JSON template files and sets the variables.
    - Creates a user managed identity, and configured the RBAC for it with two new custom roles.
    - Assigns the VM Image Builder App identity, a Contributor role to the staging group.
.PARAMETER <name>
    Parameter explanation
.EXAMPLE
    PS C:\> <example usage>
    Explanation of what the example does
.NOTES
    Author: Patryk Podlas
    Created: 04/05/2023

    Change history:
    Date            Author      V       Notes
    04/05/2023      PP          1.0     First release
#>
function Build-AzureVMImageBuilder {
    [CmdletBinding()]
    param (
        $Location = "uksouth",
        $ImageResourceGroup = "rg-vmimagebuilder",
        $StagingImageResourceGroup = "rg-vmimagebuilder-staging",
        $vNetResourceGroupName = "rg-vmimagebuilder", # Can be different if you wish to create the vNET in a different resource group.
        $ComputeGalleryName = "cgvmibimages", # Compute gallery name.
        $ImageDefinitionName = "windows_11_gen2_generic", # Name of the image definition within the image gallery.
        $VMGeneration = "V2",
        $ImageRoleDefinitionName = "Developer Azure Image Builder Image Definition",
        $NetworkRoleDefinitionName = "Developer Azure Image Builder Network Definition",
        $IdentityName = "umi-vmimagebuilder",
        $RunOutputName = "windows_11_gen2_generic", # Name of the output to manipulate later, I suggest it to be the same as the definition name, with perhaps the version name.
        $vNETName = "vnet-vmimagebuilder",
        $SubnetName = "snet-vnet-vmimagebuilder",
        $NSGName = "nsg-snet-vmimagebuilder",
        $CompanyName = "Company" # Specify your company name.
    )

    begin {
        # Copy templates from the templates folder.
        Get-ChildItem -Path "./templates" | Copy-item -Destination .
        # Set the TLS version.
        $TLS12Protocol = [System.Net.SecurityProtocolType] 'Tls12'
        [System.Net.ServicePointManager]::SecurityProtocol = $TLS12Protocol
        # Install required module and import it.
        Install-Module -Name Az.ManagedServiceIdentity -Confirm:$False -Force
        Import-Module -Name Az.ManagedServiceIdentity
        Import-Module Az.Accounts
        Register-PSRepository -Default -InstallationPolicy Trusted
        'Az.ImageBuilder', 'Az.ManagedServiceIdentity' | ForEach-Object { Install-Module -Name $_ -AllowPrerelease }
        Write-Output "Check your browser and login to the Azure portal." ; Connect-AzAccount
        Get-AzContext # Set AzContext to the subscription you're going to work with if required using "Set-AzContext"
        $AZContext = Get-AzContext
        $SubscriptionID = $AZContext.Subscription.Id
        $Providers = @(
            "Microsoft.VirtualMachineImages"
            "Microsoft.Storage"
            "Microsoft.Compute"
            "Microsoft.KeyVault"
        )
        $GalleryParameters = @{
            GalleryName       = $ComputeGalleryName
            ResourceGroupName = $ImageResourceGroup
            Location          = $Location
            Name              = $ImageDefinitionName
            OsState           = 'generalized'
            OsType            = 'Windows'
            Publisher         = $CompanyName
            Offer             = 'windows_11_gen2' # Specify the offering, for example windows_11_gen2 or windows_10_gen1.
            Sku               = 'generic' # Specify the SKU this is going to be under, for example: developer, or end-user.
            HyperVGeneration  = $VMGeneration
        }
        # Get the Azure Virtual Machine Image Builder App ID.
        $VMIBAppServicePrincipal = Get-AzADServicePrincipal -Filter "DisplayName eq 'Azure Virtual Machine Image Builder'"
    }

    process {
        # Register providers
        foreach ($Provider in $Providers) {
            $Table = Get-AzResourceProvider -ProviderNamespace $Provider | Select-Object -Property ProviderNamespace, ResourceTypes, RegistrationState
            foreach ($Entry in $Table) {
                if ($Entry.RegistrationState -eq "Registered") {
                    Write-Output "Provider: $($Entry.ProviderNamespace) of resource type $($Entry.ResourceTypes.ResourceTypeName) is already registered"
                } else {
                    Write-Output "Provider: $($Entry.ProviderNamespace) of resource type $($Entry.ResourceTypes.ResourceTypeName) is not yet registered, registering"
                    Register-AzResourceProvider -ProviderNamespace $($Entry.ProviderNamespace)
                }
            }
        }

        # Create a resource group for all the resources related to Azure VM Image Builder.
        New-AzResourceGroup -Name $ImageResourceGroup -Location $Location
        # Create a staging resource for the temporary resources created as part of the image build process.
        New-AzResourceGroup -Name $StagingImageResourceGroup -Location $Location
        # Create Azure Compute Gallery.
        New-AzGallery -GalleryName $ComputeGalleryName -ResourceGroupName $ImageResourceGroup -Location $Location
        # Create Azure Compute Gallery image definition.
        New-AzGalleryImageDefinition @GalleryParameters
        # Configure networking.
        New-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $vNetResourceGroupName -Location $Location
        $NSG = Get-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $vNetResourceGroupName
        $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.0.1.0/24" -PrivateLinkServiceNetworkPoliciesFlag "Disabled" -NetworkSecurityGroup $NSG
        New-AzVirtualNetwork -Name $vNETName -ResourceGroupName $vNetResourceGroupName -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $Subnet
        Get-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $vNetResourceGroupName  | Add-AzNetworkSecurityRuleConfig -Name AzureImageBuilderAccess -Description "Allow Image Builder Private Link Access to Proxy VM" -Access Allow -Protocol Tcp -Direction Inbound -Priority 400 -SourceAddressPrefix AzureLoadBalancer -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 60000-60001 | Set-AzNetworkSecurityGroup
        $VirtualNetwork = Get-AzVirtualNetwork -Name $vNETName -ResourceGroupName $vNetResourceGroupName
        ($VirtualNetwork | Select-Object -ExpandProperty subnets | Where-Object { $_.Name -eq $SubnetName } ).privateLinkServiceNetworkPolicies = "Disabled"
        $VirtualNetwork | Set-AzVirtualNetwork

        # Set the paths for the .JSON file templates.
        $TemplateFilePath = "windows_11_gen2_generic.json"
        $AVIBRoleNetworkJoinPath = "avib_role_network_join.json"
        $AVIBRoleImageCreationPath = "avib_role_image_creation.json"

        # Update image template .JSON file.
        ((Get-Content -Path $TemplateFilePath -Raw) -replace '<subscriptionID>', $SubscriptionID) | Set-Content -Path $TemplateFilePath
        ((Get-Content -Path $TemplateFilePath -Raw) -replace '<rgName>', $ImageResourceGroup) | Set-Content -Path $TemplateFilePath
        ((Get-Content -Path $TemplateFilePath -Raw) -replace '<stagingrgName>', $StagingImageResourceGroup) | Set-Content -Path $TemplateFilePath
        ((Get-Content -Path $TemplateFilePath -Raw) -replace '<region>', $Location) | Set-Content -Path $TemplateFilePath
        ((Get-Content -Path $TemplateFilePath -Raw) -replace '<runOutputName>', $runOutputName) | Set-Content -Path $TemplateFilePath
        ((Get-Content -Path $TemplateFilePath -Raw) -replace '<imageDefinitionName>', $ImageDefinitionName) | Set-Content -Path $TemplateFilePath
        ((Get-Content -Path $TemplateFilePath -Raw) -replace '<vnetName>', $vNETName) | Set-Content -Path $TemplateFilePath
        ((Get-Content -Path $TemplateFilePath -Raw) -replace '<subnetName>', $SubnetName) | Set-Content -Path $TemplateFilePath
        ((Get-Content -Path $TemplateFilePath -Raw) -replace '<vnetRgName>', $vNetResourceGroupName) | Set-Content -Path $TemplateFilePath
        ((Get-Content -Path $TemplateFilePath -Raw) -replace '<umiName>', $IdentityName) | Set-Content -Path $TemplateFilePath
        ((Get-Content -Path $TemplateFilePath -Raw) -replace '<galleryName>', $ComputeGalleryName) | Set-Content -Path $TemplateFilePath


        # Create user managed identity.
        New-AzUserAssignedIdentity -ResourceGroupName $ImageResourceGroup -Name $IdentityName -Location $Location ; Start-Sleep -Seconds 60
        $IdentityNamePrincipalId = $(Get-AzUserAssignedIdentity -ResourceGroupName $ImageResourceGroup -Name $IdentityName).PrincipalId
        # Update the role template with the idenity information and roles.
        ((Get-Content -Path $AVIBRoleImageCreationPath -Raw) -replace 'Azure Image Builder Service Image Creation Role', $ImageRoleDefinitionName) | Set-Content -Path $AVIBRoleImageCreationPath
        ((Get-Content -Path $AVIBRoleNetworkJoinPath -Raw) -replace 'Azure Image Builder Service Networking Role', $NetworkRoleDefinitionName) | Set-Content -Path $AVIBRoleNetworkJoinPath
        # Update role definitions .JSON template file.
        ((Get-Content -Path $AVIBRoleNetworkJoinPath -Raw) -replace '<subscriptionID>', $SubscriptionID) | Set-Content -Path $AVIBRoleNetworkJoinPath
        ((Get-Content -Path $AVIBRoleNetworkJoinPath -Raw) -replace '<vnetRgName>', $vNetResourceGroupName) | Set-Content -Path $AVIBRoleNetworkJoinPath
        ((Get-Content -Path $AVIBRoleImageCreationPath -Raw) -replace '<subscriptionID>', $SubscriptionID) | Set-Content -Path $AVIBRoleImageCreationPath
        ((Get-Content -Path $AVIBRoleImageCreationPath -Raw) -replace '<rgName>', $ImageResourceGroup) | Set-Content -Path $AVIBRoleImageCreationPath
        # Create role definitions.
        New-AzRoleDefinition -InputFile  "./$AVIBRoleImageCreationPath"
        New-AzRoleDefinition -InputFile  "./$AVIBRoleNetworkJoinPath"
        # Assign the roles to the user managed identity.
        New-AzRoleAssignment -ObjectId $IdentityNamePrincipalId -RoleDefinitionName $ImageRoleDefinitionName -Scope "/subscriptions/$SubscriptionID/resourceGroups/$ImageResourceGroup"
        New-AzRoleAssignment -ObjectId $IdentityNamePrincipalId -RoleDefinitionName $NetworkRoleDefinitionName -Scope "/subscriptions/$SubscriptionID/resourceGroups/$vNetResourceGroupName"
        # Assign the Contributor role to the Azure VM Image Builder App on the staging resource group scope.
        New-AzRoleAssignment -ObjectId $VMIBAppServicePrincipal.Id -RoleDefinitionName "Contributor" -Scope "/subscriptions/$SubscriptionID/resourceGroups/$StagingImageResourceGroup"
    }

    end {

    }
}