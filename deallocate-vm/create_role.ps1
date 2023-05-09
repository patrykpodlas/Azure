$SubscriptionID = "" # Provide the subscription ID: (Get-AzContext).Subscription.Id

$role = [Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition]::new()
$role.Name = 'Deallocate VM when user logs off'
$role.Description = 'This custom role will allow your virtual machines to be deallocated when the user logs off.'
$role.IsCustom = $true
$perms = 'Microsoft.Compute/virtualMachines/deallocate/action'
$role.Actions = $perms
$subs = "/subscriptions/$SubscriptionID"
$role.AssignableScopes = $subs
New-AzRoleDefinition -Role $role