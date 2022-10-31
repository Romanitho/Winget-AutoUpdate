<#
.SYNOPSIS
Handle user interaction from shortcuts and show a Toast

.DESCRIPTION
Act on shortcut run (DEFAULT: Check for updated Apps)

.PARAMETER Logs
Open the Log file from Winget-AutoUpdate installation location

.PARAMETER Help
Open the Web Help page
https://github.com/Romanitho/Winget-AutoUpdate

.EXAMPLE
.\user-run.ps1 -Logs

#>

[CmdletBinding()]
param(
	[Parameter(Mandatory = $False)] [Switch] $Logs = $false,
	[Parameter(Mandatory = $False)] [Switch] $Help = $false
)

function Test-WAUisRunning {
	If (((Get-ScheduledTask -TaskName 'Winget-AutoUpdate').State -eq 'Running') -or ((Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext').State -eq 'Running')) {
		Return $True
	}
}

<# FUNCTIONS #>

#Get Working Dir
$Script:WorkingDir = $PSScriptRoot

Get-ChildItem "$WorkingDir\functions" | ForEach-Object { . $_.FullName }

function Test-WAUisRunning {
	If (((Get-ScheduledTask -TaskName 'Winget-AutoUpdate').State -eq 'Running') -or ((Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext').State -eq 'Running')) {
		Return $True
	}
}

<# MAIN #>

#Run log initialisation function
Start-Init
Write-Log "User run initiated"

#Get Toast Locale function
Get-NotifLocale | Out-Null

#Get WingetCmd function
Get-WingetCmd | Out-Null

#Get WAU Configurations
$Script:WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"

if ($Logs) {
	if ((Test-Path "$WorkingDir\logs\updates.log")) {
		Invoke-Item "$WorkingDir\logs\updates.log"
	}
	else {
		#Not available yet
		$Message = $NotifLocale.local.outputs.output[5].message
		$MessageType = "warning"
		Start-NotifTask -Message $Message -MessageType $MessageType
	}
}
elseif ($Help) {
	Start-Process "https://github.com/Romanitho/Winget-AutoUpdate"
}
else {
	try {
		#Check if WAU is currently running
		if (Test-WAUisRunning) {
			$Message = $NotifLocale.local.outputs.output[8].message
			$MessageType = "warning"
			$Button1Text = $NotifLocale.local.outputs.output[11].message
			$Button1Action = "$WorkingDir\logs\updates.log"
			Start-NotifTask -Message $Message -MessageType $MessageType -Button1Text $Button1Text -Button1Action $Button1Action -ButtonDismiss
			break
		}

		#Get Outdated apps
		$Outdated = Get-WingetOutdatedApps
		$OutdatedApps = @()
		#If White List
		if ($WAUConfig.WAU_UseWhiteList -eq 1) {
			$toUpdate = Get-IncludedApps
			foreach ($app in $Outdated) {
				if (($toUpdate -contains $app.Id) -and $($app.Version) -ne "Unknown") {
					$OutdatedApps += $app.Name
				}
			}
		}
		#If Black List or default
		else {
			$toSkip = Get-ExcludedApps
			foreach ($app in $Outdated) {
				if (-not ($toSkip -contains $app.Id) -and $($app.Version) -ne "Unknown") {
					$OutdatedApps += $app.Name
				}
			}
		}
		$body = $OutdatedApps | Out-String
		if ($body) {
			Start-NotifTask -Title "New available updates" -Message "Do you want to update these apps ?" -Body $body -ButtonDismiss -Button1Text "Yes" -Button1Action "wau:" -MessageType "info"
		}
		else {
			Start-NotifTask -Title "All good." -Message "No new update available" -MessageType "success"
		}
	}
	catch {
		#Check failed - Just send notification
		$Message = $NotifLocale.local.outputs.output[7].message
		$MessageType = "error"
		Start-NotifTask -Message $Message -MessageType $MessageType -Button1Text $Button1Text -Button1Action $OnClickAction -ButtonDismiss
	}
}
