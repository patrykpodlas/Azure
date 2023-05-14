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
.PARAMETER Location
    Azure region.
    .PARAMETER ImageResourceGroup
    Resource group which will contain all the permament resources.
    .PARAMETER StagingImageResourceGroup
    Resource group which will contain all the termporary resources created by the Azure VM Image Builder service.
    .PARAMETER vNetResourceGroup
    Resource group which will contain the networking components to be used by Azure VM Image Builder service, this can be different if you wish to create the resources in a different resource group, for simplicity I like to keep it all under the same group.
    .PARAMETER GalleryName
    Azure Compute Gallery name.
    .PARAMETER <name>
    Parameter explanation
    .PARAMETER <name>
    Parameter explanation
.EXAMPLE
Build-AVIBEnvironment `
    -Location "uksouth" `
    -ImageResourceGroup "rg-vmimagebuilder" `
    -StagingImageResourceGroup "rg-vmimagebuilder-staging" `
    -vNetResourceGroup "rg-vmimagebuilder" `
    -GalleryName "cgvmibimages" `
    -ImageDefinitionName "windows_11_gen2_generic" `
    -VMGeneration "V2" `
    -ImageRoleDefinitionName "Azure Image Builder Image Creation Definition" `
    -NetworkRoleDefinitionName "Azure Image Builder Network Join Definition" `
    -AVIBRoleNetworkJoinPath "avib_role_network_join.json" `
    -AVIBRoleImageCreationPath "avib_role_image_creation.json" `
    -IdentityName "umi-vmimagebuilder" `
    -RunOutputName "windows_11_gen2_generic" `
    -vNETName "vnet-vmimagebuilder" `
    -SubnetName "snet-vnet-vmimagebuilder" `
    -NSGName "nsg-snet-vmimagebuilder" `
    -CompanyName "Company" `
    -Verbose
.NOTES
    Author: Patryk Podlas
    Created: 04/05/2023

    Change history:
    Date            Author      V       Notes
    04/05/2023      PP          1.0     First release
#>
function Build-AVIBEnvironment {
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $Location,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $ImageResourceGroup,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $StagingImageResourceGroup,
        $vNetResourceGroup,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $GalleryName,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $ImageDefinitionName,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $VMGeneration,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $ImageRoleDefinitionName,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $AVIBRoleImageCreationPath,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $NetworkRoleDefinitionName,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $AVIBRoleNetworkJoinPath,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $IdentityName,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $vNETName,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $SubnetName,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $NSGName,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $CompanyName,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $RunOutputName
    )

    begin {
        # Set the TLS version.
        $TLS12Protocol = [System.Net.SecurityProtocolType] 'Tls12'
        [System.Net.ServicePointManager]::SecurityProtocol = $TLS12Protocol

        # Copy templates from the templates folder.
        Get-ChildItem -Path "./role_templates" | Copy-item -Destination "."

        # Install required module and import it.
        Install-Module -Name Az.ManagedServiceIdentity -Confirm:$False -Force
        Import-Module -Name Az.ManagedServiceIdentity
        Import-Module Az.Accounts
        Register-PSRepository -Default -InstallationPolicy Trusted
        'Az.ImageBuilder', 'Az.ManagedServiceIdentity' | ForEach-Object { Install-Module -Name $_ -AllowPrerelease }
        Write-Verbose "Check your browser and login to the Azure portal." ; Connect-AzAccount
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
            GalleryName       = $GalleryName
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
                    Write-Verbose "Provider: $($Entry.ProviderNamespace) of resource type $($Entry.ResourceTypes.ResourceTypeName) is already registered"
                } else {
                    Write-Verbose "Provider: $($Entry.ProviderNamespace) of resource type $($Entry.ResourceTypes.ResourceTypeName) is not yet registered, registering"
                    Register-AzResourceProvider -ProviderNamespace $($Entry.ProviderNamespace)
                }
            }
        }

        # Create a resource group for all the resources related to Azure VM Image Builder.
        Write-Verbose "Creating resource group: $ImageResourceGroup." ; New-AzResourceGroup -Name $ImageResourceGroup -Location $Location
        # Create a staging resource for the temporary resources created as part of the image build process.
        Write-Verbose "Creating resource group: $StagingImageResourceGroup." ; New-AzResourceGroup -Name $StagingImageResourceGroup -Location $Location
        # Create Azure Compute Gallery.
        Write-Verbose "Creating Azure Compute Gallery: $GalleryName in resource group $ImageResourceGroup" ; New-AzGallery -GalleryName $GalleryName -ResourceGroupName $ImageResourceGroup -Location $Location
        # Create Azure Compute Gallery image definition.
        Write-Verbose "Creating Azure Compute Gallery image definition: $ImageDefinitionName" ; New-AzGalleryImageDefinition @GalleryParameters
        # Configure networking.
        New-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $vNetResourceGroup -Location $Location
        $NSG = Get-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $vNetResourceGroup
        $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.0.1.0/24" -PrivateLinkServiceNetworkPoliciesFlag "Disabled" -NetworkSecurityGroup $NSG
        New-AzVirtualNetwork -Name $vNETName -ResourceGroupName $vNetResourceGroup -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $Subnet
        Get-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $vNetResourceGroup  | Add-AzNetworkSecurityRuleConfig -Name AzureImageBuilderAccess -Description "Allow Image Builder Private Link Access to Proxy VM" -Access Allow -Protocol Tcp -Direction Inbound -Priority 400 -SourceAddressPrefix AzureLoadBalancer -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 60000-60001 | Set-AzNetworkSecurityGroup
        $VirtualNetwork = Get-AzVirtualNetwork -Name $vNETName -ResourceGroupName $vNetResourceGroup
        ($VirtualNetwork | Select-Object -ExpandProperty subnets | Where-Object { $_.Name -eq $SubnetName } ).privateLinkServiceNetworkPolicies = "Disabled"
        $VirtualNetwork | Set-AzVirtualNetwork

        # Create user managed identity.
        New-AzUserAssignedIdentity -ResourceGroupName $ImageResourceGroup -Name $IdentityName -Location $Location ; Start-Sleep -Seconds 60
        $IdentityNamePrincipalId = $(Get-AzUserAssignedIdentity -ResourceGroupName $ImageResourceGroup -Name $IdentityName).PrincipalId

        # Update the role template with the idenity information and roles.
        ((Get-Content -Path $AVIBRoleImageCreationPath -Raw) -replace 'Azure Image Builder Image Creation Definition', $ImageRoleDefinitionName) | Set-Content -Path $AVIBRoleImageCreationPath
        ((Get-Content -Path $AVIBRoleNetworkJoinPath -Raw) -replace 'Azure Image Builder Network Join Definition', $NetworkRoleDefinitionName) | Set-Content -Path $AVIBRoleNetworkJoinPath

        # Update role definitions .JSON template file.
        ((Get-Content -Path $AVIBRoleNetworkJoinPath -Raw) -replace '<SubscriptionID>', $SubscriptionID) | Set-Content -Path $AVIBRoleNetworkJoinPath
        ((Get-Content -Path $AVIBRoleNetworkJoinPath -Raw) -replace '<vNETResourceGroup>', $vNetResourceGroup) | Set-Content -Path $AVIBRoleNetworkJoinPath
        ((Get-Content -Path $AVIBRoleImageCreationPath -Raw) -replace '<SubscriptionID>', $SubscriptionID) | Set-Content -Path $AVIBRoleImageCreationPath
        ((Get-Content -Path $AVIBRoleImageCreationPath -Raw) -replace '<ImageResourceGroup>', $ImageResourceGroup) | Set-Content -Path $AVIBRoleImageCreationPath

        # Create role definitions.
        New-AzRoleDefinition -InputFile  "./$AVIBRoleImageCreationPath"
        New-AzRoleDefinition -InputFile  "./$AVIBRoleNetworkJoinPath"

        # Assign the roles to the user managed identity.
        New-AzRoleAssignment -ObjectId $IdentityNamePrincipalId -RoleDefinitionName $ImageRoleDefinitionName -Scope "/subscriptions/$SubscriptionID/resourceGroups/$ImageResourceGroup"
        New-AzRoleAssignment -ObjectId $IdentityNamePrincipalId -RoleDefinitionName $NetworkRoleDefinitionName -Scope "/subscriptions/$SubscriptionID/resourceGroups/$vNetResourceGroup"
        New-AzRoleAssignment -ObjectId $IdentityNamePrincipalId -RoleDefinitionName "Contributor" -Scope "/subscriptions/$SubscriptionID/resourceGroups/$StagingImageResourceGroup"

        # Assign the Contributor role to the Azure VM Image Builder App on the staging resource group scope.
        New-AzRoleAssignment -ObjectId $VMIBAppServicePrincipal.Id -RoleDefinitionName "Contributor" -Scope "/subscriptions/$SubscriptionID/resourceGroups/$StagingImageResourceGroup"
    }

    end {
        Write-Verbose "Cleaning up the temporary role template files."
        Get-Item -Path ./avib_role_image_creation.json, ./avib_role_network_join.json | Remove-Item
    }
}