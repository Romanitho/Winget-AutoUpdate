#Write to Log Function

function Write-ToLog {

    [CmdletBinding()]
    param(
        [Parameter()] [String] $LogMsg,
        [Parameter()] [String] $LogColor = "White",
        [Parameter()] [Switch] $IsHeader = $false
    )

    #Create file if doesn't exist
    if (!(Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null

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

    #If header requested
    if ($IsHeader) {
        $Log = "#" * 65 + "`n#    $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) - $LogMsg`n" + "#" * 65
    }
    else {
        $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    }

    #Echo log
    $Log | Write-host -ForegroundColor $LogColor

    #Write log to file
    $Log | Out-File -FilePath $LogFile -Append

}
