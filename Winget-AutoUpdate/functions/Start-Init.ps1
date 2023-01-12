#Initialisation

function Start-Init {

    #Config console output encoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # Maximum number of log files to keep. Default is 3. Setting MaxLogFiles to 0 will keep all log files.
    [int32] $MaxLogFiles = 3
    
    # Maximum size of log file.
    [int64] $MaxLogSize = 1048576 # in bytes, default is 1048576 = 1 MB

    #Log Header
    $Log = "`n##################################################`n#     CHECK FOR APP UPDATES - $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern)`n##################################################"
    $Log | Write-host

    #Logs initialisation
    $Script:LogFile = "$WorkingDir\logs\updates.log"

    if (!(Test-Path $LogFile)) {
        #Create file if doesn't exist
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

    #LogRotation if System
    if ($IsSystem) {
        Invoke-LogRotation $LogFile $MaxLogFiles $MaxLogSize
    }

    #Log file
    $Log | out-file -filepath $LogFile -Append

}
