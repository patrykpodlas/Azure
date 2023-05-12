# VM Image Builder
Build an entire VM Image Builder environment, using best practises.
# Deallocate VM
Used to automatically de-allocate VM in Azure when user logs off.
## How to use
1. Connect to Azure using `Connect-AzAccount`.
2. Execute `create_role.ps1`.
3. Assign the role to the VM's in the host pool using `Set-ManagedIdentity.ps1`.
4. Use Intune to run the full_script.ps1 on every VM in the hosts pool.