<#
.SYNOPSIS
    Manages log file rotation and archival.

.DESCRIPTION
    Rotates log files when they exceed the maximum size, archiving old
    logs with timestamps. Maintains a configurable maximum number of
    archived log files by deleting the oldest when necessary.

.PARAMETER LogFile
    Full path to the log file to manage.

.PARAMETER MaxLogFiles
    Maximum number of log files to keep (0 = unlimited, 1 = no rotation).

.PARAMETER MaxLogSize
    Maximum log file size in bytes before rotation occurs.

.OUTPUTS
    Boolean: True on success, False if an error occurred.

.EXAMPLE
    Invoke-LogRotation "C:\logs\updates.log" 3 1048576

.NOTES
    Archived logs are named with timestamp: filename_yyyyMMddHHmmss.ext
#>
function Invoke-LogRotation {
    [OutputType([Bool])]
    param(
        [string]$LogFile,
        [Int32]$MaxLogFiles,
        [Int64]$MaxLogSize
    )

    # If MaxLogFiles is 1, keep original file without rotation (let it grow)
    if (-not($MaxLogFiles -eq 1)) {
        try {
            # Get current log file size
            $currentSize = (Get-Item $LogFile).Length

            # Parse log file path components
            $logFileName = Split-Path $LogFile -Leaf
            $logFilePath = Split-Path $LogFile
            $logFileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($logFileName)
            $logFileNameExtension = [System.IO.Path]::GetExtension($logFileName)

            # Check if rotation is needed
            if ($currentSize -ge $MaxLogSize) {

                # Create archived filename with timestamp
                $newLogFileName = $logFileNameWithoutExtension + (Get-Date -Format 'yyyyMMddHHmmss').ToString() + $logFileNameExtension

                # Rename current log to archived name
                Rename-Item -Path $LogFile -NewName $newLogFileName -Force -Confirm:$false

                # Create new empty log file
                Write-ToLog "New log file created"

                # Clean up old archives if MaxLogFiles > 0
                if (-not($MaxLogFiles -eq 0)) {

                    # Build filter pattern for archived log files
                    $archivedLogFileFilter = $logFileNameWithoutExtension + '??????????????' + $logFileNameExtension

                    # Find all archived log files
                    $oldLogFiles = Get-Item -Path "$(Join-Path -Path $logFilePath -ChildPath $archivedLogFileFilter)"

                    if ([bool]$oldLogFiles) {
                        # Delete oldest files if count exceeds maximum
                        if (($oldLogFiles.Count + 1) -gt $MaxLogFiles) {
                            [int]$numTooMany = (($oldLogFiles.Count) + 1) - $MaxLogFiles
                            $oldLogFiles | Sort-Object 'LastWriteTime' | Select-Object -First $numTooMany | Remove-Item
                        }
                    }
                }

                # Log rotation event
                Write-ToLog -LogMsg "CHECK FOR APP UPDATES (System context)" -IsHeader
                Write-ToLog -LogMsg "Max Log Size reached: $MaxLogSize bytes - Rotated Logs"
            }

            Return $true
        }
        catch {
            Return $false
        }
    }
}
