<#
.SYNOPSIS
    Custom modifications for Winget-AutoUpdate (WAU)
    Runs if Network is active/any Winget is installed/running as SYSTEM

    If mods\_WAU-mods.ps1 exist: Winget-Upgrade.ps1 calls this script with the code:
    [Write-ToLog "Running Mods for WAU..." "Cyan"

    # Capture both output and exit code
    $ModsOutput = & "$Mods\_WAU-mods.ps1" 2>&1 | Out-String
    $ModsExitCode = $LASTEXITCODE]

.DESCRIPTION
    This script runs before the main WAU process and can control WAU execution
    by returning a JSON object with action instructions.
    
    The script should output a JSON object with the following structure:
    {
        "Action": "string",         // Required: Action for WAU to perform
        "Message": "string",        // Optional: Message to write to WAU log
        "LogLevel": "string",       // Optional: Log level for the message
        "ExitCode": number,         // Optional: Windows installer exit code for reference
        "PostponeDuration": number, // Optional: Postpone duration in hours before running WAU again (default 1 hour)
        "RebootDelay": number,      // Optional: Delay in minutes before rebooting (default 5 minutes)
        "RebootHandler": string     // Optional: "SCCM" or "Windows" (default "Windows") to specify reboot handler
    }
    
    Available Actions:
    - "Continue"   : Continue with normal WAU execution (default behavior)
    - "Abort"      : Abort WAU execution completely
    - "Postpone"   : Postpone WAU execution temporarily with 'PostponeDuration' hours
    - "Rerun"      : Re-run WAU (equivalent to legacy exit code 1)
    - "Reboot"     : Restart the system with delay and notification to end user
    
    Available LogLevels:
    - "White"      : Default/normal message
    - "Green"      : Success message
    - "Yellow"     : Warning message
    - "Red"        : Error message
    - "Cyan"       : Information message
    - "Magenta"    : Debug message
    
    Standard Windows Installer Exit Codes (for reference):
    - 0            : Success
    - 1602         : User cancelled installation
    - 1618         : Another installation is in progress
    - 3010         : Restart required (SCCM Soft Reboot)
    - 1641         : Restart initiated by installer (SCCM Hard Reboot)
    
    Examples:
    
    # Example 1: Abort on specific day
    $result = @{
        Action = "Abort"
        Message = "WAU disabled on maintenance day"
        LogLevel = "Yellow"
        ExitCode = 1602
    } | ConvertTo-Json -Compress
    
    # Example 2: Postpone WAU execution
    $result = @{
        Action = "Postpone"
        Message = "WAU postponed due to maintenance schedule"
        LogLevel = "Yellow"
        ExitCode = 1602
        PostponeDuration = 2  # Optional: Postpone WAU execution for 2 hours (default is 1 hour)
    } | ConvertTo-Json -Compress

    # Example 3: Continue normally
    $result = @{
        Action = "Continue"
        Message = "All checks passed, proceeding with updates"
        LogLevel = "Green"
    } | ConvertTo-Json -Compress

    # Example 4: Request reboot after checks
    $result = @{
        Action = "Reboot"
        Message = "The system needs to reboot within 15 minutes before WAU updates can be performed."
        LogLevel = "Red"
        ExitCode = 1641  # Optional: Use 1641 for SCCM Hard Reboot (default is 3010 for Soft Reboot)
        RebootDelay = 15  # Optional: Delay before rebooting (default is 5 minutes)
        RebootHandler = "SCCM"  # Optional: Specify reboot handler (default is "Windows")
    } | ConvertTo-Json -Compress

.NOTES
    - This script must always exit with code 0 when using JSON output
    - Legacy exit code 1 is still supported for backward compatibility
    - Only the first valid JSON object in output will be processed
    - If JSON parsing fails, WAU will continue normally
    - Make sure your Functions have unique names to avoid conflicts
    - Beware of logic loops or long-running operations that may loop indefinitely or block WAU execution!
#>


<# FUNCTIONS #>
. $PSScriptRoot\_Mods-Functions.ps1


<# ARRAYS/VARIABLES #>


<# MAIN #>
# Add your custom logic here

<#
# Example implementation: Second Tuesday of month check
$today = Get-Date
$firstDayOfMonth = [DateTime]::new($today.Year, $today.Month, 1)
$firstTuesday = $firstDayOfMonth.AddDays((2 - [int]$firstDayOfMonth.DayOfWeek + 7) % 7)
$secondTuesday = $firstTuesday.AddDays(7)

if ($today.Date -ne $secondTuesday.Date) {
    # Not second Tuesday - abort WAU execution
    $result = @{
        Action = "Abort"
        Message = "Today is not the second Tuesday of the month. WAU execution aborted."
        LogLevel = "Yellow"
        ExitCode = 1602  # User cancelled
    } | ConvertTo-Json -Compress
    
    Write-Output $result
    Exit 0
}

# Example: Check if maintenance window is active
$maintenanceStart = Get-Date "02:00"
$maintenanceEnd = Get-Date "04:00"
$currentTime = Get-Date

if ($currentTime -ge $maintenanceStart -and $currentTime -le $maintenanceEnd) {
    $result = @{
        Action = "Abort"
        Message = "WAU aborted during maintenance window ($($maintenanceStart.ToString('HH:mm')) - $($maintenanceEnd.ToString('HH:mm')))"
        LogLevel = "Yellow"
        ExitCode = 1602
    } | ConvertTo-Json -Compress
    
    Write-Output $result
    Exit 0
}

# Example: Check available disk space
$systemDrive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
$freeSpaceGB = [math]::Round($systemDrive.Free / 1GB, 2)
$minimumSpaceGB = 5

if ($freeSpaceGB -lt $minimumSpaceGB) {
    $result = @{
        Action = "Abort"
        Message = "Insufficient disk space: ${freeSpaceGB}GB available, ${minimumSpaceGB}GB required"
        LogLevel = "Red"
        ExitCode = 1618  # Another installation is in progress (or system busy)
    } | ConvertTo-Json -Compress
    
    Write-Output $result
    Exit 0
}

# Example: Check Windows Update registry keys for installation status
$wuInProgress = $false
$wuKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending"
)

foreach ($key in $wuKeys) {
    if (Test-Path $key) {
        $lastInstall = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($lastInstall -and $lastInstall.PSObject.Properties.Name -contains "LastSuccessTime" -and $lastInstall.LastSuccessTime) {
            try {
                $lastSuccessTime = [DateTime]$lastInstall.LastSuccessTime
                # If the last successful install was within the last 30 minutes, consider WU in progress
                if ((Get-Date).AddMinutes(-30) -lt $lastSuccessTime) {
                    $wuInProgress = $true
                    break
                }
            }
            catch {
                # Failed to parse date, skip this check
                continue
            }
        }
    }
}

# Check if Windows Update service is running
$wuInProgress = $wuInProgress -or (Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue).Status -eq "Running"

# Check for specific Windows Update processes (TiWorker and TrustedInstaller are strong indicators)
$wuInProgress = $wuInProgress -or (Get-Process -Name "TiWorker","TrustedInstaller" -ErrorAction SilentlyContinue).Count -gt 0

if ($wuInProgress) {
    $result = @{
        Action = "Postpone"
        Message = "Windows Update is currently installing. WAU postponed for 2 hours."
        LogLevel = "Yellow"
        ExitCode = 1618
        PostponeDuration = 2
    } | ConvertTo-Json -Compress

    Write-Output $result
    Exit 0
}

# All checks passed - continue with normal WAU execution
$result = @{
    Action = "Continue"
    Message = "Second Tuesday check passed. No maintenance window. Sufficient disk space (${freeSpaceGB}GB). No Windows Update in progress. Continuing with WAU execution."
    LogLevel = "Green"
} | ConvertTo-Json -Compress

Write-Output $result
Exit 0
#>
