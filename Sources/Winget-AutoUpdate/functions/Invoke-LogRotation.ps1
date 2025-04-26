#Function to rotate the logs

function Invoke-LogRotation {
    [OutputType([Bool])]
    param(
        [string]$LogFile, 
        [Int32]$MaxLogFiles, 
        [Int64]$MaxLogSize
    )

    # if MaxLogFiles is 1 just keep the original one and let it grow
    if (-not($MaxLogFiles -eq 1)) {
        try {
            # get current size of standard log file
            $currentSize = if (Test-Path $LogFile) { (Get-Item $LogFile).Length } else { 0 }

            # get standard log name
            $logFileName = Split-Path $LogFile -Leaf
            $logFilePath = Split-Path $LogFile
            $logFileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($logFileName)
            $logFileNameExtension = [System.IO.Path]::GetExtension($logFileName)

            if ($currentSize -ge $MaxLogSize) {
                $logrotate = $true

                # construct name of archived log file
                $newLogFileName = $logFileNameWithoutExtension + (Get-Date -Format 'yyyyMMddHHmmss').ToString() + $logFileNameExtension
                # rename old log file
                Rename-Item -Path $LogFile -NewName $newLogFileName -Force -Confirm:$false

                # if MaxLogFiles is 0 don't delete any old archived log files
                if (-not($MaxLogFiles -eq 0)) {

                    # set filter to search for archived log files
                    $archivedLogFileFilter = $logFileNameWithoutExtension + '??????????????' + $logFileNameExtension

                    # get archived log files
                    $oldLogFiles = Get-Item -Path "$(Join-Path -Path $logFilePath -ChildPath $archivedLogFileFilter)"

                    if ([bool]$oldLogFiles) {
                        # compare found log files to MaxLogFiles parameter of the log object, and delete oldest until we are
                        # back to the correct number
                        if (($oldLogFiles.Count + 1) -gt $MaxLogFiles) {
                            [int]$numTooMany = (($oldLogFiles.Count) + 1) - $MaxLogFiles
                            $oldLogFiles | Sort-Object 'LastWriteTime' | Select-Object -First $numTooMany | Remove-Item
                        }
                    }
                }
            }

            # CM log file name
            $CMLogFile = $LogFile -replace "\.log$", "_CM.log"

            # get current size of CM log file if it exists
            if (Test-Path $CMLogFile) {
                $currentCMSize = if (Test-Path $CMLogFile) { (Get-Item $CMLogFile).Length } else { 0 }

                # get CM log name
                $logFileName = Split-Path $CMLogFile -Leaf
                $logFilePath = Split-Path $CMLogFile
                $logFileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($logFileName)
                $logFileNameExtension = [System.IO.Path]::GetExtension($logFileName)

                if ($currentCMSize -ge $MaxLogSize) {
                    $CM_logrotate = $true

                    # construct name of archived log file
                    $newLogFileName = $logFileNameWithoutExtension + (Get-Date -Format 'yyyyMMddHHmmss').ToString() + $logFileNameExtension
                    # rename old log file
                    Rename-Item -Path $CMLogFile -NewName $newLogFileName -Force -Confirm:$false

                    # if MaxLogFiles is 0 don't delete any old archived log files
                    if (-not($MaxLogFiles -eq 0)) {

                        # set filter to search for archived log files
                        $archivedLogFileFilter = $logFileNameWithoutExtension + '??????????????' + $logFileNameExtension

                        # get archived log files
                        $oldLogFiles = Get-Item -Path "$(Join-Path -Path $logFilePath -ChildPath $archivedLogFileFilter)"

                        if ([bool]$oldLogFiles) {
                            # compare found log files to MaxLogFiles parameter of the log object, and delete oldest until we are
                            # back to the correct number
                            if (($oldLogFiles.Count + 1) -gt $MaxLogFiles) {
                                [int]$numTooMany = (($oldLogFiles.Count) + 1) - $MaxLogFiles
                                $oldLogFiles | Sort-Object 'LastWriteTime' | Select-Object -First $numTooMany | Remove-Item
                            }
                        }
                    }
                }
            }

            # Log actions
            if ($logrotate) {
                Write-ToLog "###   Max Standard log size reached: $MaxLogSize bytes - Rotated Logs   ###"
            }
            if ($CM_logrotate) {
                Write-ToLog "###   Max CM log size reached: $MaxLogSize bytes - Rotated CM Logs   ###"
            }  

            # end of try block
            Return $true;
        }
        catch {
            Return $false;
        }
    }
}
