#Requires -Version 5.1
# Launches the SYSTEM-owned update prompt in the exact session recorded by the
# protected pending-update inventory.
$Script:WorkingDir = $PSScriptRoot
Get-ChildItem -Path "$Script:WorkingDir\functions" -File -Filter '*.ps1' | ForEach-Object { . $_.FullName }
$Script:IsSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
if (-not $Script:IsSystem) { throw 'The update prompt launcher must run as SYSTEM.' }
$LogFile = Join-Path $Script:WorkingDir 'logs\updates.log'
$pendingPath = Join-Path $Script:WorkingDir 'config\pending-updates.json'
if (-not (Test-Path -LiteralPath $pendingPath)) { exit 0 }
$pending = Get-Content -LiteralPath $pendingPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
$userSid = [string]$pending.Config.UserSid
$sessionId = Get-WauInteractiveSessionId -UserSid $userSid
if (-not $sessionId) { Write-ToLog "No unambiguous active session found for $userSid." 'Yellow'; exit 1 }
$serviceUI = Join-Path $Script:WorkingDir 'ServiceUI.exe'
if (-not (Test-Path -LiteralPath $serviceUI -PathType Leaf)) { Write-ToLog 'ServiceUI.exe is missing.' 'Red'; exit 1 }
$promptCommand = "& '$([IO.Path]::Combine($Script:WorkingDir, 'WAU-UpdatePrompt.ps1'))'"
$encodedPrompt = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($promptCommand))
$powershell = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
Start-Process -FilePath $serviceUI `
    -ArgumentList "-nowait -session:$sessionId $powershell -NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -EncodedCommand $encodedPrompt" `
    -WorkingDirectory $Script:WorkingDir -ErrorAction Stop | Out-Null
Write-ToLog "Update prompt launcher targeted session $sessionId."