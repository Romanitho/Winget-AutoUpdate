#Function to rotate the logs

function Invoke-LogRotation ($LogFile, $MaxLogFiles, $MaxLogSize) {

    # if MaxLogFiles is 1 just keep the original one and let it grow
    if (-not($MaxLogFiles -eq 1)) {

        try {
            # get current size of log file
            $currentSize = (Get-Item $LogFile).Length

            # get log name
            $logFileName = Split-Path $LogFile -Leaf
            $logFilePath = Split-Path $LogFile
            $logFileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($logFileName)
            $logFileNameExtension = [System.IO.Path]::GetExtension($logFileName)

            if ($currentSize -ge $MaxLogSize) {

                # construct name of archived log file
                $newLogFileName = $logFileNameWithoutExtension + (Get-Date -Format 'yyyyMMddHHmmss').ToString() + $logFileNameExtension
                # rename old log file
                Rename-Item -Path $LogFile -NewName $newLogFileName -Force -Confirm:$false

                # create new file
                Write-ToLog "New log file created"

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

                #Log Header
                Write-ToLog -LogMsg "CHECK FOR APP UPDATES (System context)" -IsHeader
                Write-ToLog -LogMsg "Max Log Size reached: $MaxLogSize bytes - Rotated Logs"

                Return $True
            }
        }

        catch {
            Return $False
        }

    }

}
