#Initialisation

function Start-Init {

    #Config console output encoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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

    #Log file
    $Log | out-file -filepath $LogFile -Append

}
