#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{32}$')][string]$RequestId)

$Script:WorkingDir = $PSScriptRoot
Get-ChildItem "$PSScriptRoot\functions" -Filter '*.ps1' -File | ForEach-Object { . $_.FullName }
$Script:IsSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
if ($Script:IsSystem) { throw 'The user worker must not run as SYSTEM.' }
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$directory = Join-Path $PSScriptRoot "config\scope-requests\$RequestId"
$request = Get-Content (Join-Path $directory 'request.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
if ($request.UserSid -ne $sid -or $request.RequestId -ne $RequestId) { throw 'Request belongs to another user or run.' }
$logDirectory = Join-Path $env:LOCALAPPDATA 'Winget-AutoUpdate\Logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$LogFile = Join-Path $logDirectory "scope-$RequestId.log"
New-Item -ItemType File -Path $LogFile -Force | Out-Null
$response = [pscustomobject]@{ RequestId=$RequestId; UserSid=$sid; Success=$false; Apps=@(); Error='' }
try {
    $Script:Winget = Get-WingetCmd
    if (-not $Script:Winget) { throw 'WinGet was not found in the user context.' }
    $Script:WAUConfig = Get-WAUConfig
    $Script:WingetSourceCustom = $request.Source
    if ($request.Operation -eq 'Scan') {
        $response.Apps = @(Get-WingetOutdatedApps -src $request.Source -Scope user)
        foreach ($app in $response.Apps) {
            $userSupport = Get-WauInstallerSupport -App $app -Scope user -Source $request.Source
            $machineSupport = if ($userSupport -eq 'Unavailable') {
                Get-WauInstallerSupport -App $app -Scope machine -Source $request.Source
            } else { 'Unknown' }
            $app | Add-Member NoteProperty UserInstallerSupport $userSupport -Force
            $app | Add-Member NoteProperty MachineInstallerSupport $machineSupport -Force
        }
    }
    elseif ($request.Operation -eq 'Plan') {
        $fresh = @(Get-WingetOutdatedApps -src $request.Source -Scope user)
        $planned = @()
        foreach ($selected in @($request.Apps)) {
            $app = $fresh | Where-Object { $_.Key -eq $selected.Key -and $_.AvailableVersion -eq $selected.AvailableVersion } | Select-Object -First 1
            if (-not $app) { continue }
            $userSupport = Get-WauInstallerSupport -App $app -Scope user -Source $request.Source
            $machineSupport = if ($userSupport -eq 'Unavailable') {
                Get-WauInstallerSupport -App $app -Scope machine -Source $request.Source
            } else { 'Unknown' }
            $planned += [pscustomobject]@{
                Key=$app.Key; Id=$app.Id; AvailableVersion=$app.AvailableVersion
                UserInstallerSupport=$userSupport
                MachineInstallerSupport=$machineSupport
            }
        }
        $response.Apps = $planned
    }
    elseif ($request.Operation -eq 'Update') {
        $null = Get-NotifLocale
        $Script:InstallOK = 0
        $fresh = @(Get-WingetOutdatedApps -src $request.Source -Scope user)
        $completed = @()
        foreach ($selected in @($request.Apps)) {
            $app = $fresh | Where-Object { $_.Key -eq $selected.Key -and $_.AvailableVersion -eq $selected.AvailableVersion } | Select-Object -First 1
            if (-not $app) { Write-ToLog "Selected update changed or disappeared: $($selected.Id)" 'Yellow'; continue }
            $before = $Script:InstallOK
            Update-App $app -src $request.Source
            if ($Script:InstallOK -gt $before) { $completed += [pscustomobject]@{ Key=$app.Key; Id=$app.Id } }
        }
        $response.Apps = $completed
    }
    else { throw 'Unknown user operation.' }
    $response.Success = $true
}
catch { $response.Error = $_.Exception.Message; Write-ToLog $response.Error 'Red' }
Write-WauAtomicJson (Join-Path $directory 'response\result.json') $response
if (-not $response.Success) { exit 1 }
