<#
.SYNOPSIS
    Installs pending updates selected by the user via the WAU deadline prompt.

.DESCRIPTION
    Runs in SYSTEM context as the Winget-AutoUpdate-UpdateNow scheduled task.
    Triggered when the user clicks "Update Now" in the WAU deadline prompt dialog.

    Reads the list of apps to update from config\update-request.json (written by
    the SYSTEM GUI), processes each app through WAU's standard Update-App pipeline
    (which preserves scope and verifies the selected version), then cleans up registry
    deadline entries for apps that were successfully updated.

    Initialization mirrors Winget-Upgrade.ps1 so that Update-App and its dependencies
    (Start-NotifTask, Write-ToLog, Confirm-Installation, etc.) have all required
    script-scoped variables in scope.

.NOTES
    Scheduled task: Winget-AutoUpdate-UpdateNow
    Run as:         SYSTEM (S-1-5-18), RunLevel Highest
    Trigger:        On demand (started by WAU-UpdatePrompt.ps1)
    Instances:      IgnoreNew (only one instance at a time)
#>

#region LOAD FUNCTIONS
[string]$Script:WorkingDir = $PSScriptRoot

Get-ChildItem -Path "$Script:WorkingDir\functions" -File -Filter "*.ps1" -Depth 0 |
    ForEach-Object { . $_.FullName }
#endregion LOAD FUNCTIONS

#region INITIALIZATION
$null = & "$env:WINDIR\System32\cmd.exe" /c ""
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

[string]$LogFile = [System.IO.Path]::Combine($Script:WorkingDir, 'logs', 'updates.log')
#endregion INITIALIZATION

#region CONTEXT AND CONFIG
[bool]$Script:IsSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
if (-not $Script:IsSystem) { throw 'UpdateNow must run as SYSTEM.' }

Write-ToLog -LogMsg "USER-INITIATED UPDATE" -IsHeader

$Script:WAUConfig = Get-WAUConfig

[string]$Script:WingetSourceCustom = 'winget'
if (-not [string]::IsNullOrWhiteSpace($Script:WAUConfig.WAU_WingetSourceCustom)) {
    $Script:WingetSourceCustom = $Script:WAUConfig.WAU_WingetSourceCustom.Trim()
}

[string]$LocaleDisplayName = Get-NotifLocale
Write-ToLog "Notification Level: $($Script:WAUConfig.WAU_NotificationLevel). Notification Language: $LocaleDisplayName" "Cyan"
#endregion CONTEXT AND CONFIG

#region WINGET
[string]$Script:Winget = Get-WingetCmd

if (-not $Script:Winget) {
    Write-ToLog "Critical: Winget not found -- cannot process updates" "Red"
    Exit 1
}

Write-ToLog "Selected winget instance: $Script:Winget"
#endregion WINGET

# Atomically claim the protected GUI request. Never read update instructions from
# the user-writable legacy ProgramData CSV/JSON files.
$requestPath = Join-Path $Script:WorkingDir 'config\update-request.json'
if (-not (Test-Path -LiteralPath $requestPath)) { exit 0 }
$claimedPath = Join-Path $Script:WorkingDir ('config\update-running-' + [guid]::NewGuid().ToString('N') + '.json')
Move-Item -LiteralPath $requestPath -Destination $claimedPath -ErrorAction Stop
$Script:InstallOK = 0
try {
    $request = Get-Content -LiteralPath $claimedPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([datetime]::UtcNow - [datetime]::Parse($request.CreatedUtc).ToUniversalTime() -gt [timespan]::FromHours(2)) { throw 'Update selection expired. Please scan again.' }
    $source = $Script:WingetSourceCustom
    $freshMachine = @(Get-WingetOutdatedApps -src $source -Scope machine)
    $freshUser = @()
    if (@($request.Apps | Where-Object { $_.Scope -eq 'user' -and $_.TargetScope -eq 'machine' }).Count) {
        $freshUser = @(Invoke-WauUserOperation -Operation Scan -UserSid $request.UserSid)
    }
    $userSelected = @()
    foreach ($selected in @($request.Apps)) {
        if ($selected.Key -ne (Get-WauAppKey $selected) -or $selected.Source -ne $source) { continue }
        if ($selected.Scope -eq 'machine') {
            $app = $freshMachine | Where-Object { $_.Key -eq $selected.Key -and $_.AvailableVersion -eq $selected.AvailableVersion } | Select-Object -First 1
            if (-not $app) { Write-ToLog "Machine update changed/disappeared: $($selected.Id)" 'Yellow'; continue }
        }
        elseif ($selected.Scope -eq 'user' -and $selected.UserSid -eq $request.UserSid) {
            if ($selected.TargetScope -eq 'machine' -and $selected.ScopeMigrationApproved -eq $true) {
                if (-not @($freshUser | Where-Object { $_.Id -eq $selected.Id -and $_.Version -eq $selected.Version -and $_.AvailableVersion -eq $selected.AvailableVersion -and $_.UserInstallerSupport -eq 'Unavailable' }).Count) {
                    Write-ToLog "User installation changed; migration cancelled: $($selected.Id)" 'Yellow'; continue
                }
                # This consent originates only in the SYSTEM-owned GUI request.
                # Update-App rechecks both installer scopes at the selected version.
                $app = $selected
            }
            else { $userSelected += $selected; continue }
        }
        else { Write-ToLog 'Invalid scope or user identity in update selection.' 'Red'; continue }
        $reason = Get-WauBlockReason $app
        if ($reason) { Write-ToLog "$($app.Id): $reason" 'Yellow'; continue }
        $before = $Script:InstallOK
        Update-App $app -src $source
        if ($Script:InstallOK -gt $before) {
            Remove-WauUpdateDeadline -App $app
            if ($app.Scope -eq 'user') { Write-ToLog "Machine installation confirmed. Original user installation was retained: $($app.Id)" 'Yellow' }
        }
    }
    if ($userSelected.Count -gt 0) {
        $allowed = @($userSelected | Where-Object { -not (Get-WauBlockReason $_) })
        if ($allowed.Count -gt 0) {
            $completed = @(Invoke-WauUserOperation -Operation Update -UserSid $request.UserSid -Apps $allowed -TimeoutSeconds 10800)
            foreach ($entry in $completed) {
                # A user response can only acknowledge one of its approved user updates.
                if ($entry.Key -in @($allowed | ForEach-Object Key)) {
                    $completedApp = $allowed | Where-Object Key -eq $entry.Key | Select-Object -First 1
                    if ($completedApp) { Remove-WauUpdateDeadline -App $completedApp }
                }
            }
            Write-ToLog "$($completed.Count) user updates confirmed."
        }
    }
}
catch { Write-ToLog "Update request failed: $_" 'Red'; exit 1 }
finally {
    # Keep a private audit record of the exact version/scope consent and execution.
    Move-Item -LiteralPath $claimedPath -Destination ($claimedPath -replace 'update-running-', 'update-completed-') -Force -ErrorAction SilentlyContinue
}
Write-ToLog 'End of scoped update request.' 'Cyan'


