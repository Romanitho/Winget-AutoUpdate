<#
.SYNOPSIS
Writing to log files and console with formatting and color options.

.DESCRIPTION
This function handles logging to multiple destinations - standard log file, Configuration Manager log file, Windows Event Log, and console output.
It supports color-coded output, headers, and different log levels.

.PARAMETER LogMsg
The message to log.

.PARAMETER LogColor
The color to use for console output.
Available colors: Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White

.PARAMETER IsHeader
Switch to format the message as a header with surrounding '#' characters.

.PARAMETER Component
The component name to use in Configuration Manager log format.

.PARAMETER LogLevel
The log level to use:
0 = Verbose
1 = Information (default)
2 = Warning
3 = Error
4 = None

.PARAMETER LogSource
The source name for the Windows Event Log.

.PARAMETER UseCMLog
Whether to use Configuration Manager log format.

.PARAMETER UseEventLog
Whether to write to the Windows Event Log.

.EXAMPLE
# Standard use (all three destinations)
Write-ToLog "Installing $AppID..." "DarkYellow"

.EXAMPLE
# Extra Configuration Manager details
Write-ToLog -LogMsg "Installing $AppID..." -LogColor "DarkYellow" -Component "AppInstaller" -LogLevel "1"

.EXAMPLE
# Without Event Log
Write-ToLog -LogMsg "Debug information" -LogColor "Gray" -UseEventLog $false

.EXAMPLE
# As header
Write-ToLog "NEW INSTALL REQUEST" "RoyalBlue" -IsHeader -Component "WinGet-Install"
#>

function Write-ToLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$LogMsg,
        [string]$LogColor = "White",
        [switch]$IsHeader,
        [string]$Component = "WAU",
        [string]$LogLevel = "1",  # 0=Verbose, 1=Information, 2=Warning, 3=Error, 4=None
        [string]$LogSource = "WAU",
        [bool]$UseCMLog = $false,
        [bool]$UseEventLog = $true
    )

    if ((Test-Path -Path "$env:windir\CCM\CMTrace.exe") -or (Test-Path -Path "${env:ProgramFiles(x86)}\Configuration Manager Support Center\CMLogViewer.exe")) {
        # If either CMTrace or CMLogViewer is installed, set $UseCMLog = $true
        $UseCMLog = $true
    }

    # If the log file path does not exist, set it to the local log path
    # Set file paths
    $StandardLogFile = $LogFile
    $CMLogFile = $LogFile -replace "\.log$", "_CM.log"

    # Create directory if it doesn't exist
    if (!(Test-Path (Split-Path $StandardLogFile))) {
        New-Item -ItemType Directory -Force -Path (Split-Path $StandardLogFile) | Out-Null
    }

    # Create standard log file if doesn't exist
    if (!(Test-Path $StandardLogFile)) {
        New-Item -ItemType File -Path $StandardLogFile -Force | Out-Null

        #Set ACL for users on standard logfile
        $NewAcl = Get-Acl -Path $StandardLogFile
        $identity = New-Object System.Security.Principal.SecurityIdentifier S-1-5-11
        $fileSystemRights = "Modify"
        $type = "Allow"
        $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
        $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
        $NewAcl.SetAccessRule($fileSystemAccessRule)
        Set-Acl -Path $StandardLogFile -AclObject $NewAcl
    }

    # Create Configuration Manager log file if doesn't exist
    if (!(Test-Path $CMLogFile) -and $UseCMLog) {
        New-Item -ItemType File -Path $CMLogFile -Force | Out-Null

        #Set ACL for users on Configuration Manager logfile
        $NewAcl = Get-Acl -Path $CMLogFile
        $identity = New-Object System.Security.Principal.SecurityIdentifier S-1-5-11
        $fileSystemRights = "Modify"
        $type = "Allow"
        $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
        $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
        $NewAcl.SetAccessRule($fileSystemAccessRule)
        Set-Acl -Path $CMLogFile -AclObject $NewAcl
    }

    # 1. Standard log format
    $FormattedDate = Get-Date -Format "HH:mm:ss"
    $StandardLogLine = "$FormattedDate $LogMsg"

    # If header requested, format and write to console and standard log file
    # Note: The big header is not written to the CM log file or Event log, as it is not in the correct format
    if ($IsHeader) {
        $Log = "#" * 65 + "`n#    $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) - $LogMsg`n" + "#" * 65
        Write-Host $Log -ForegroundColor $LogColor
        # Write log to file
        $Log | Out-File -FilePath $StandardLogFile -Append

        # Set a small header for CM/Event log
        if ($UseCMLog -or $UseEventLog) {
            $LogMsg = "###   $LogMsg   ###"
        }
    }
    else {
        Write-Host $StandardLogLine -ForegroundColor $LogColor
        $StandardLogLine | Out-File -FilePath $StandardLogFile -Append
    }

    # 2. Configuration Manager log format
    if ($UseCMLog) {
        $time = Get-Date -Format "HH:mm:ss.fff+000"
        $date = Get-Date -Format "MM-dd-yyyy"
        #$ProcessID = $PID.ToString().PadLeft(5, '0')
        $ThreadID = ([System.Threading.Thread]::CurrentThread.ManagedThreadId).ToString().PadLeft(5, '0')

        # Select log level based on color if not explicit given
        $CMLogLevel = $LogLevel
        if ($LogColor -eq "Red" -and $LogLevel -eq "1") {
            $CMLogLevel = "3"  # Error
        }
        elseif ($LogColor -eq "Yellow" -and $LogLevel -eq "1") {
            $CMLogLevel = "2"  # Warning
        }

        # Create the log entry in CM format - note the exact format needed for OneTrace
        $ComputerName = $env:COMPUTERNAME
        $Context = "Invoker: $env:USERNAME"
        $CMLogLine = "<![LOG[$LogMsg]LOG]!><time=`"$time`" date=`"$date`" component=`"$Component`" context=`"$Context`" type=`"$CMLogLevel`" thread=`"$ThreadID`" file=`"$ComputerName`">"

        # Write to CM log file
        $CMLogLine | Out-File -FilePath $CMLogFile -Append
    }

    # 3. Windows Event Log
    if ($UseEventLog) {
        # Create a log source if it doesn't exist
        if (-not [System.Diagnostics.EventLog]::SourceExists($LogSource)) {
            try {
                [System.Diagnostics.EventLog]::CreateEventSource($LogSource, "Application")
            }
            catch {
                # Silent error handling - continue
            }
        }

        # Select log level for Event Log
        $EventLogEntryType = "Information"
        if ($LogColor -eq "Red") {
            $EventLogEntryType = "Error"
        }
        elseif ($LogColor -eq "Yellow") {
            $EventLogEntryType = "Warning"
        }

        # Write to Event Log source exist
        try {
            if ([System.Diagnostics.EventLog]::SourceExists($LogSource)) {
                # Categorize event-ID based on function or measure
                $EventID = 1000  # Standard information log

                # If it is an installation message
                if ($LogMsg -match "\bInstalling\b") {
                    $EventID = 1001
                }
                # If it is an uninstall message
                elseif ($LogMsg -match "\bUninstalling\b") {
                    $EventID = 1002
                }
                # If it is a modification message
                elseif ($LogMsg -match "\bModifications\b") {
                    $EventID = 1003
                }
                # If it is an updating message
                elseif ($LogMsg -match "\bUpdating\b") {
                    $EventID = 1004
                }
                # If it is an error
                elseif ($EventLogEntryType -eq "Error") {
                    $EventID = 9000
                }

                # Use string concatenation instead of variable interpolation with colon
                $EventMessage = "$($Component): $LogMsg"
                Write-EventLog -LogName Application -Source $LogSource -EventId $EventID `
                    -EntryType $EventLogEntryType -Message $EventMessage

            }
        }
        catch {
            # Silent error handling - continue
        }
    }
}
