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
        "Action": "string",     // Required: Action for WAU to perform
        "Message": "string",    // Optional: Message to write to WAU log
        "LogLevel": "string",   // Optional: Log level for the message
        "ExitCode": number,     // Optional: Windows installer exit code for reference
        "RebootDelay": number   // Optional: Delay in seconds before rebooting (default 300 seconds (5 minutes))
    }
    
    Available Actions:
    - "Continue"   : Continue with normal WAU execution (default behavior)
    - "Abort"      : Abort WAU execution completely
    - "Rerun"      : Re-run WAU (equivalent to legacy exit code 1)
    - "Reboot"     : Restart the system immediately
    
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
    - 3010         : Restart required
    - 1641         : Restart initiated by installer
    
    Examples:
    
    # Example 1: Abort on specific day
    $result = @{
        Action = "Abort"
        Message = "WAU disabled on maintenance day"
        LogLevel = "Yellow"
        ExitCode = 1602
    } | ConvertTo-Json -Compress
    
    # Example 2: Continue normally
    $result = @{
        Action = "Continue"
        Message = "All checks passed, proceeding with updates"
        LogLevel = "Green"
    } | ConvertTo-Json -Compress
    
    # Example 3: Request reboot after checks
    $result = @{
        Action = "Reboot"
        Message = "System requires restart before updates"
        LogLevel = "Red"
        ExitCode = 3010
        RebootDelay = 300  # Optional: Delay before rebooting (default is 300 seconds)
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

# All checks passed - continue with normal WAU execution
$result = @{
    Action = "Continue"
    Message = "Second Tuesday check passed. No maintenance window. Sufficient disk space (${freeSpaceGB}GB). Continuing with WAU execution."
    LogLevel = "Green"
} | ConvertTo-Json -Compress

Write-Output $result
Exit 0
#>
