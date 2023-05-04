<#
.SYNOPSIS
    Builds the environment for Azure VM Image Builder.
.DESCRIPTION
    Builds the environment for Azure VM Image Builder.
    1. Registers the required providers.
    2. Configures a new vNET and NSG, as well as the required security rule configuration, sets the privateLinkServiceNetworkPolicies to disabled.
    3. Downloads a .JSON template from GitHub and configured it appropriately with the variables configured.
    4. Creates a user managed identity, and configured the RBAC for it with two new custom roles.
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
        $ImageResourceGroup = "rg-vmimagebuilder",
        $Location = "uksouth",
        $ImageTemplateName = "window2019VnetTemplate03",
        $ImageName = "win2019image01",
        $ImageRoleDefinitionName = "Developer Azure Image Builder Image Definition",
        $NetworkRoleDefinitionName = "Developer Azure Image Builder Network Definition",
        $IdentityName = "umi-vmimagebuilder",
        $RunOutputName = "Output",
        $vNETName = "rg-vmimagebuilder",
        $SubnetName = "snet-vnet-vmimagebuilder",
        $vNetResourceGroupName = "rg-vmimagebuilder",
        $NSGName = "nsg-snet-vmimagebuilder"
    )

    begin {
        # Set the TLS version.
        $TLS12Protocol = [System.Net.SecurityProtocolType] 'Tls12'
        [System.Net.ServicePointManager]::SecurityProtocol = $TLS12Protocol
        # Install required module and import it.
        Install-Module -Name Az.ManagedServiceIdentity -Confirm:$False -Force
        Import-Module -Name Az.ManagedServiceIdentity
        Import-Module Az.Accounts
        Register-PSRepository -Default -InstallationPolicy Trusted
        'Az.ImageBuilder', 'Az.ManagedServiceIdentity' | ForEach-Object { Install-Module -Name $_ -AllowPrerelease }
        Connect-AzAccount
        Get-AzContext # Set AzContext to the subscription you're going to work with if required using "Set-AzContext"
        $AZContext = Get-AzContext
        $SubscriptionID = $AZContext.Subscription.Id
        $Providers = @(
            "Microsoft.VirtualMachineImages"
            "Microsoft.Storage"
            "Microsoft.Compute"
            "Microsoft.KeyVault"
        )
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

        New-AzResourceGroup -Name $ImageResourceGroup -Location $Location ; Start-Sleep -Seconds 15
        # New-AzResourceGroup -Name $vNetResourceGroupName -Location $Location ; Start-Sleep -Seconds 15
        New-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $vNetResourceGroupName -Location $Location
        $NSG = Get-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $vNetResourceGroupName
        $Subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.0.1.0/24" -PrivateLinkServiceNetworkPoliciesFlag "Disabled" -NetworkSecurityGroup $NSG
        New-AzVirtualNetwork -Name $vNETName -ResourceGroupName $vNetResourceGroupName -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $Subnet
        Get-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $vNetResourceGroupName  | Add-AzNetworkSecurityRuleConfig -Name AzureImageBuilderAccess -Description "Allow Image Builder Private Link Access to Proxy VM" -Access Allow -Protocol Tcp -Direction Inbound -Priority 400 -SourceAddressPrefix AzureLoadBalancer -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 60000-60001 | Set-AzNetworkSecurityGroup
        $VirtualNetwork = Get-AzVirtualNetwork -Name $vNETName -ResourceGroupName $vNetResourceGroupName
        ($VirtualNetwork | Select-Object -ExpandProperty subnets | Where-Object { $_.Name -eq $SubnetName } ).privateLinkServiceNetworkPolicies = "Disabled"
        $VirtualNetwork | Set-AzVirtualNetwork


        $TemplateUrl = "https://raw.githubusercontent.com/azure/azvmimagebuilder/master/quickquickstarts/1a_Creating_a_Custom_Win_Image_on_Existing_VNET/existingVNETWindows.json"
        $TemplateFilePath = "ExistingVNETWindows.json"
        $AVIBRoleNetworkingUrl = "https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleNetworking.json"
        $AVIBRoleNetworkingPath = "aibRoleNetworking.json"
        $AVIBRoleImageCreationUrl = "https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json"
        $AVIBRoleImageCreationPath = "aibRoleImageCreation.json"

        Invoke-WebRequest -Uri $TemplateURL -OutFile $TemplateFilePath -UseBasicParsing
        Invoke-WebRequest -Uri $AVIBRoleNetworkingUrl -OutFile $AVIBRoleNetworkingPath -UseBasicParsing
        Invoke-WebRequest -Uri $AVIBRoleImageCreationUrl -OutFile $AVIBRoleImageCreationPath -UseBasicParsing

        ((Get-Content -path $TemplateFilePath -Raw) -replace '<subscriptionID>', $SubscriptionID) | Set-Content -Path $TemplateFilePath
        ((Get-Content -path $TemplateFilePath -Raw) -replace '<rgName>', $ImageResourceGroup) | Set-Content -Path $TemplateFilePath
        ((Get-Content -path $TemplateFilePath -Raw) -replace '<region>', $Location) | Set-Content -Path $TemplateFilePath
        ((Get-Content -path $TemplateFilePath -Raw) -replace '<runOutputName>', $runOutputName) | Set-Content -Path $TemplateFilePath
        ((Get-Content -path $TemplateFilePath -Raw) -replace '<imageName>', $ImageName) | Set-Content -Path $TemplateFilePath
        ((Get-Content -path $TemplateFilePath -Raw) -replace '<vnetName>', $vNETName) | Set-Content -Path $TemplateFilePath
        ((Get-Content -path $TemplateFilePath -Raw) -replace '<subnetName>', $SubnetName) | Set-Content -Path $TemplateFilePath
        ((Get-Content -path $TemplateFilePath -Raw) -replace '<vnetRgName>', $vNetResourceGroupName) | Set-Content -Path $TemplateFilePath

        # Create user managed identity.
        New-AzUserAssignedIdentity -ResourceGroupName $ImageResourceGroup -Name $IdentityName -Location $Location ; Start-Sleep -Seconds 60
        $IdentityNameResourceId = $(Get-AzUserAssignedIdentity -ResourceGroupName $ImageResourceGroup -Name $IdentityName).Id
        $IdentityNamePrincipalId = $(Get-AzUserAssignedIdentity -ResourceGroupName $ImageResourceGroup -Name $IdentityName).PrincipalId
        # Update the role template with the idenity information.
        ((Get-Content -path $TemplateFilePath -Raw) -replace '<imgBuilderId>', $IdentityNameResourceId) | Set-Content -Path $TemplateFilePath
        ((Get-Content -path $AVIBRoleImageCreationPath -Raw) -replace 'Azure Image Builder Service Image Creation Role', $ImageRoleDefinitionName) | Set-Content -Path $AVIBRoleImageCreationPath
        ((Get-Content -path $AVIBRoleNetworkingPath -Raw) -replace 'Azure Image Builder Service Networking Role', $NetworkRoleDefinitionName) | Set-Content -Path $AVIBRoleNetworkingPath
        # Update role definitions.
        ((Get-Content -path $AVIBRoleNetworkingPath -Raw) -replace '<subscriptionID>', $SubscriptionID) | Set-Content -Path $AVIBRoleNetworkingPath
        ((Get-Content -path $AVIBRoleNetworkingPath -Raw) -replace '<vnetRgName>', $vNetResourceGroupName) | Set-Content -Path $AVIBRoleNetworkingPath
        ((Get-Content -path $AVIBRoleImageCreationPath -Raw) -replace '<subscriptionID>', $SubscriptionID) | Set-Content -Path $AVIBRoleImageCreationPath
        ((Get-Content -path $AVIBRoleImageCreationPath -Raw) -replace '<rgName>', $ImageResourceGroup) | Set-Content -Path $AVIBRoleImageCreationPath
        # Create role definitions.
        New-AzRoleDefinition -InputFile  ./aibRoleImageCreation.json
        New-AzRoleDefinition -InputFile  ./aibRoleNetworking.json
        # Grant role definition to image builder user identity.
        New-AzRoleAssignment -ObjectId $IdentityNamePrincipalId -RoleDefinitionName $ImageRoleDefinitionName -Scope "/subscriptions/$SubscriptionID/resourceGroups/$ImageResourceGroup"
        New-AzRoleAssignment -ObjectId $IdentityNamePrincipalId -RoleDefinitionName $NetworkRoleDefinitionName -Scope "/subscriptions/$SubscriptionID/resourceGroups/$vNetResourceGroupName"
    }

    end {

    }
}






