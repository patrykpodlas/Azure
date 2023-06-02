#sign-me
<#
.SYNOPSIS
    Creates a scheduled task that will de-allocate the VM when the logged in user logs off, should another not be logged in at the same time.
.DESCRIPTION
    Creates a scheduled task that will de-allocate the VM when the logged in user logs off, should another not be logged in at the same time.
    It will also set the MaxDisconnectionTime, and MaxIdleTime to 2 hours, which when triggered, will also log off the user and thus execute the script.
    This will ensure the VM is not running and cuts costs.
    The script gets created in C:\_scripts directory.
    Ideally to be deployed through Intune.
    You must pre-create the custom role using the create_role.ps1, and then assign it to every virtual machine in the hosts pool using the Set-ManagedIdentity function.
    You will have to re-run the function for every new host in the host pool, or add it as part of the process when adding new hosts.
    1. Create the role using the create_role.ps1
    2. Assign the role using Set-ManagedIdentity.ps1
    3. Use Intune to run the full_script.ps1 on every VM in the hosts pool.
.NOTES
    Author: Patryk Podlas
    Credit: BerndLoehlein
    Created: 09/05/2023

    Change history:
    Date            Author      V       Notes
    09/05/2023      PP          1.0     First release
#>

# Create the content of the script for the next step.
[string]$Script = @'
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
'@

# Create the script using the content above.
New-Item -Path 'C:\_scripts' -Name 'deallocate-vm.ps1' -ItemType File -Value $Script -Force

# Create a trigger based on the event 4647
$Class = Get-cimclass MSFT_TaskEventTrigger root/Microsoft/Windows/TaskScheduler
$Trigger = $Class | New-CimInstance -ClientOnly
$Trigger.Enabled = $true
$Trigger.Subscription = '<QueryList><Query Id="0" Path="Security"><Select Path="Security">*[System[EventID=4647]]</Select></Query></QueryList>'

$ActionParameters = @{
    Execute  = 'C:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe'
    Argument = '-NoProfile -File C:\_scripts\deallocate-vm.ps1' # Specify the script location.
}

$Action = New-ScheduledTaskAction @ActionParameters
$Principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount
$Settings = New-ScheduledTaskSettingsSet

$RegSchTaskParameters = @{
    TaskName    = 'Deallocate VM when user logs off'
    Description = 'Runs at user logoff'
    TaskPath    = '\Event Viewer Tasks\'
    Action      = $Action
    Principal   = $Principal
    Settings    = $Settings
    Trigger     = $Trigger
}

Register-ScheduledTask @RegSchTaskParameters

$Time = 7200000 # 2h
Set-ItemProperty "registry::HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\" -Name "MaxDisconnectionTime" -Value $Time
Set-ItemProperty "registry::HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\" -Name "MaxIdleTime" -Value $Time