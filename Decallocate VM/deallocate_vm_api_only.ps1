$MetaData = Invoke-RestMethod -Headers @{"Metadata" = "true" } -Method GET -Proxy $Null -Uri "http://169.254.169.254/metadata/instance?api-version=2021-01-01"
$AuthorizationToken = Invoke-RestMethod -Headers @{"Metadata" = "true" } -Method Get -Proxy $Null -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-01-01&resource=https://management.azure.com/"

$SubscriptionId = $MetaData.Compute.SubscriptionId
$ResourceGroupName = $MetaData.Compute.ResourceGroupName
$VMName = $MetaData.Compute.Name
$accessToken = $AuthorizationToken.access_token

$RestartEvents = Get-EventLog -LogName System -After (Get-Date).AddMinutes(-1) | Where-Object { ($_.EventID -eq 1074) -and ($_.Message -match "restart" ) }
$SessionCount = (query user | Measure-Object | Select-Object Count).count - 1 # remove headline

if (($SessionCount -gt 1) -or ($RestartEvents.count -ge 1)) {
    # skip deallocate because of user-sessions or initiated reboot
} else {
    Invoke-WebRequest -UseBasicParsing -Headers @{ Authorization = "Bearer $accessToken" } -Method POST -Proxy $Null -Uri https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$VMName/deallocate?api-version=2021-03-01 -ContentType "application/json"
}