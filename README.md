# VM Image Builder
Build an entire VM Image Builder environment, using best practises.
## How to use
1. Start with `Build-AVIBEnvironment`, you can simply execute using the example, make sure you're in the `VM Image Builder/setup` directory.
``` powershell
Build-AVIBEnvironment `
    -Location "uksouth" `
    -ImageResourceGroup "rg-vmimagebuilder" ` # Name of the resource group which will contain all of the AVIB permament resources.
    -StagingImageResourceGroup "rg-vmimagebuilder-staging" ` # Name of the resource group which will contain all of the AVIB temporary resources.
    -vNetResourceGroup "rg-vmimagebuilder" ` # Can be different if you wish to create the vNET in a different resource group.
    -GalleryName "cgvmibimages" ` # Compute gallery name which will store the images.
    -ImageDefinitionName "windows_11_gen2_generic" ` # Name of the image definition within the image gallery.
    -VMGeneration "V2" ` # For Windows 11 leave as V2. You can't mix and match VM generations in the same compute gallery.
    -ImageRoleDefinitionName "Developer Azure Image Builder Image Definition" `
    -NetworkRoleDefinitionName "Developer Azure Image Builder Network Definition" `
    -AVIBRoleNetworkJoinPath "avib_role_network_join.json" `
    -AVIBRoleImageCreationPath "avib_role_image_creation.json" `
    -IdentityName "umi-vmimagebuilder" `
    -RunOutputName "windows_11_gen2_generic" ` # Name of the output to manipulate later, I suggest it to be the same as the definition name, with perhaps the version name.
    -vNETName "vnet-vmimagebuilder" `
    -SubnetName "snet-vnet-vmimagebuilder" `
    -NSGName "nsg-snet-vmimagebuilder" `
    -CompanyName "Company" ` # Specify your company name.
```
2. Once the environment finishes building, switch to `VM Image Builder` directory, and execute `Build-AVIBTemplate.ps1`. The creation of the template is instant,
``` powershell
    Build-AVIBTemplate `
        -TemplateFilePath "./image_templates/windows_11_gen2_generic.json" `
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
```
3. Within the same directory, execute `Build-AVIBImage` and wait, the entire process takes around 70 minutes complete, this is due to the fact the VM uses HDD and the service needs to upload the image to the compute gallery.
``` powershell
    Build-AVIBImage `
        -BuildVersion "1.0.0" `
        -ImageResourceGroup "rg-vmimagebuilder" `
        -StagingImageResourceGroup "rg-vmimagebuilder-staging"
        -TemplateFilePath "./windows_11_gen2_generic/windows_11_gen2_generic.json" `
```
# Deallocate VM
Used to automatically de-allocate VM in Azure when user logs off.
## How to use
1. Connect to Azure using `Connect-AzAccount`.
2. Execute `create_role.ps1`.
3. Assign the role to the VM's in the host pool using `Set-ManagedIdentity.ps1`.
4. Use Intune to run the `full_script.ps1` on every VM in the hosts pool.