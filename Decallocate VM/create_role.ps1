$SubscriptionID = "" # Provide the subscription ID: (Get-AzContext).Subscription.Id

$Role = [Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition]::new()
$Role.Name = 'Deallocate VM when user logs off'
$Role.Description = 'This custom role will allow your virtual machines to be deallocated when the user logs off.'
$Role.IsCustom = $true
$Permissions = 'Microsoft.Compute/virtualMachines/deallocate/action'
$Role.Actions = $Permissions
$Subs = "/subscriptions/$SubscriptionID"
$Role.AssignableScopes = $Subs
New-AzRoleDefinition -Role $role