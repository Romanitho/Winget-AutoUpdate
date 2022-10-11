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
	[Parameter(Mandatory=$False)] [Switch] $Logs = $false,
	[Parameter(Mandatory=$False)] [Switch] $Help = $false
)

<# MAIN #>

#Get Working Dir
$Script:WorkingDir = $PSScriptRoot

#Load functions
. $PSScriptRoot\functions\Get-NotifLocale.ps1
. $PSScriptRoot\functions\Start-NotifTask.ps1

#Set common variables
$OnClickAction = "$PSScriptRoot\logs\updates.log"
$Title = "Winget-AutoUpdate (WAU)"
$Balise = "Winget-AutoUpdate (WAU)"
$userrun = $True

#Get Toast Locale function
Get-NotifLocale

if ($Logs) {
	if ((Test-Path "$PSScriptRoot\logs\updates.log")) {
		Invoke-Item "$PSScriptRoot\logs\updates.log"
	}
	else {
		#Not available yet
		$Message = $NotifLocale.local.outputs.output[5].message
		$MessageType = "warning"
		Start-NotifTask $Title $Message $MessageType $Balise
	}
}
elseif ($Help) {
	Start-Process "https://github.com/Romanitho/Winget-AutoUpdate"
}
else {
	try {
		#Run scheduled task
		Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction Stop | Start-ScheduledTask -ErrorAction Stop
		#Starting check - Send notification
		$Message = $NotifLocale.local.outputs.output[6].message
		$MessageType = "info"
		Start-NotifTask $Title $Message $MessageType $Balise $OnClickAction
	}
	catch {
		#Check failed - Just send notification
		$Message = $NotifLocale.local.outputs.output[7].message
		$MessageType = "error"
		Start-NotifTask $Title $Message $MessageType $Balise
	}
}
