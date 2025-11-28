<#
.SYNOPSIS
    Handles user-initiated WAU update checks via shortcut.

.DESCRIPTION
    Provides a user-facing interface to manually trigger WAU update checks.
    Displays toast notifications for status updates (starting, running,
    completed, or error). Waits for the scheduled task to complete and
    shows the result.

.EXAMPLE
    .\User-Run.ps1

.NOTES
    Triggered by desktop shortcut or Start menu entry.
    Uses the Winget-AutoUpdate scheduled task.
    Shows error details from logs\error.txt if update check fails.
#>

# Check if WAU is currently running
function Test-WAUisRunning {
    If (((Get-ScheduledTask -TaskName 'Winget-AutoUpdate').State -eq 'Running') -or ((Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext').State -eq 'Running')) {
        Return $True
    }
}

<# MAIN #>

# Set working directory
$Script:WorkingDir = $PSScriptRoot

# Load required functions
. $WorkingDir\functions\Get-NotifLocale.ps1
. $WorkingDir\functions\Start-NotifTask.ps1

# Load notification locale
Get-NotifLocale

# Set common notification parameters
$OnClickAction = "$WorkingDir\logs\updates.log"
$Button1Text = $NotifLocale.local.outputs.output[11].message

try {
    # Check if WAU is already running
    if (Test-WAUisRunning) {
        $Message = $NotifLocale.local.outputs.output[8].message
        $MessageType = "warning"
        Start-NotifTask -Message $Message -MessageType $MessageType -Button1Text $Button1Text -Button1Action $OnClickAction -ButtonDismiss -UserRun
        break
    }

    # Start the WAU scheduled task
    Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction Stop | Start-ScheduledTask -ErrorAction Stop

    # Send "starting" notification
    $Message = $NotifLocale.local.outputs.output[6].message
    $MessageType = "info"
    Start-NotifTask -Message $Message -MessageType $MessageType -Button1Text $Button1Text -Button1Action $OnClickAction -ButtonDismiss -UserRun

    # Wait for task completion
    While (Test-WAUisRunning) {
        Start-Sleep 3
    }

    # Check for errors in the update process
    if (Test-Path "$WorkingDir\logs\error.txt") {
        $MessageType = "error"
        $Critical = Get-Content "$WorkingDir\logs\error.txt" -Raw
        $Critical = $Critical.Trim()
        $Critical = $Critical.Substring(0, [Math]::Min($Critical.Length, 50))
        $Message = "Critical:`n$Critical..."
    }
    else {
        $MessageType = "success"
        $Message = $NotifLocale.local.outputs.output[9].message
    }
    Start-NotifTask -Message $Message -MessageType $MessageType -Button1Text $Button1Text -Button1Action $OnClickAction -ButtonDismiss -UserRun
}
catch {
    # Handle task start failure
    $Message = $NotifLocale.local.outputs.output[7].message
    $MessageType = "error"
    Start-NotifTask -Message $Message -MessageType $MessageType -Button1Text $Button1Text -Button1Action $OnClickAction -ButtonDismiss -UserRun
}
