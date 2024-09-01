#Function to rotate the logs

function Invoke-LogRotation ($LogFile, $MaxLogFiles, $MaxLogSize) {
    <#
        .SYNOPSIS
            Handle log rotation.
        .DESCRIPTION
            Invoke-LogRotation handles log rotation
        .NOTES
            Author: Øyvind Kallstad (Minimized and changed for WAU 12.01.2023 by Göran Axel Johannesson)
            URL: https://www.powershellgallery.com/packages/Communary.Logger/1.1
            Date: 21.11.2014
            Version: 1.0
    #>

    try {
        # get current size of log file
        $currentSize = (Get-Item $LogFile).Length

        # get log name
        $logFileName = Split-Path $LogFile -Leaf
        $logFilePath = Split-Path $LogFile
        $logFileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($logFileName)
        $logFileNameExtension = [System.IO.Path]::GetExtension($logFileName)

        # if MaxLogFiles is 1 just keep the original one and let it grow
        if (-not($MaxLogFiles -eq 1)) {
            if ($currentSize -ge $MaxLogSize) {

                # construct name of archived log file
                $newLogFileName = $logFileNameWithoutExtension + (Get-Date -Format 'yyyyMMddHHmmss').ToString() + $logFileNameExtension

                # copy old log file to new using the archived name constructed above
                Copy-Item -Path $LogFile -Destination (Join-Path (Split-Path $LogFile) $newLogFileName)

                # Create a new log file
                try {
                    Remove-Item -Path $LogFile -Force
                    New-Item -ItemType File -Path $LogFile -Force
                    #Set ACL for users on logfile
                    $NewAcl = Get-Acl -Path $LogFile
                    $identity = New-Object System.Security.Principal.SecurityIdentifier S-1-5-11
                    $fileSystemRights = "Modify"
                    $type = "Allow"
                    $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
                    $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
                    $NewAcl.SetAccessRule($fileSystemAccessRule)
                    Set-Acl -Path $LogFile -AclObject $NewAcl
                }
                catch {
                    Return $False
                }

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
    }
    catch {
        Return $False
    }
}
