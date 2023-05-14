# VM Image Builder
Build an entire VM Image Builder environment, using best practises.
## Using: Terraform
For anyone dabbing into Terraform, you can recreate this environment using my Terraform module! Although without the template `Build-AVIBTemplate` and image creation `Build-AVIBImage`.
Visit my Terraform repository for details.
## Using: PowerShell
1. Start with `Build-AVIBEnvironment`, you can simply execute using the example, make sure you're in the `VM Image Builder/setup` directory.
``` powershell
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
```
2. Once the environment finishes building, switch to `VM Image Builder` directory, and execute `Build-AVIBTemplate.ps1`. The creation of the template is instant,
``` powershell
    Build-AVIBTemplate `
        -TemplateFilePath "./image_templates/windows_11_gen2_generic.json" `
        -SubscriptionID "" `
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
        -StagingImageResourceGroup "rg-vmimagebuilder-staging" `
        -TemplateFilePath "./windows_11_gen2_generic/windows_11_gen2_generic.json"
```
# Deallocate VM
Used to automatically de-allocate VM in Azure when user logs off.
## How to use
1. Connect to Azure using `Connect-AzAccount`.
2. Execute `create_role.ps1`.
3. Assign the role to the VM's in the host pool using `Set-ManagedIdentity.ps1`.
4. Use Intune to run the `full_script.ps1` on every VM in the hosts pool.