function Set-ManagedIdentity {
    [CmdletBinding()]
    param (
        [string]$HostPoolName,
        [string]$ResourceGroupName,
        [string]$RoleDefinitionName = "Deallocate VM when user logs off" # The role definition must be created before.
    )

    begin {
        # Set the TLS protocol.
        $TLS12Protocol = [System.Net.SecurityProtocolType] 'Tls12'
        [System.Net.ServicePointManager]::SecurityProtocol = $TLS12Protocol
        # Connect to Azure.
        Connect-AzAccount
    }

    process {
        $SessionHosts = Get-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName
        foreach ($SessionHost in $SessionHosts) {
            # Get virtual machine by session host reference.
            $Resource = Get-AzResource -ResourceId $SessionHost.ResourceId
            $VM = Get-AzVM -ResourceGroupName $Resource.ResourceGroupName -Name $Resource.Name

            # Create system-assigned managed identiy unless it already exists.
            $ManagedIdentity = ($VM.Identity | Where-Object Type -eq "SystemAssigned").PrincipalId
            if ($ManagedIdentity -eq $Null) {
                Update-AzVM -ResourceGroupName $VM.ResourceGroupName -VM $VM -IdentityType SystemAssigned
                $ManagedIdentity = ((Get-AzVM -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name).Identity | Where-Object Type -eq "SystemAssigned").PrincipalId
            }

            # Create role-assignment unless it already exists.
            if ((Get-AzRoleAssignment -RoleDefinitionName $RoleDefinitionName -ObjectId $ManagedIdentity) -eq $Null) {
                New-AzRoleAssignment -ObjectId $ManagedIdentity -RoleDefinitionName $RoleDefinitionName -Scope $VM.Id
            }
        }
    }

    end {
        Write-Output "Finished."
    }
}