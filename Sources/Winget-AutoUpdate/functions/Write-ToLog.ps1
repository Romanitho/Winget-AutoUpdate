#Write to Log Function

function Write-ToLog {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [String] $LogMsg,
        [Parameter()] [String] $LogColor = "White",
        [Parameter()] [Switch] $IsHeader = $false
    )

    try {
        #Create file if doesn't exist
        if (!(Test-Path $LogFile)) {
            New-Item -ItemType File -Path $LogFile -Force | Out-Null

            #Set ACL for users on logfile
            $NewAcl = Get-Acl -Path $LogFile
            $identity = New-Object System.Security.Principal.SecurityIdentifier S-1-5-11
            $fileSystemAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule ($identity, "Modify", "Allow")
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
        Write-Host $Log -ForegroundColor $LogColor

        #Write log to file
        $Log | Out-File -FilePath $LogFile -Append -Encoding utf8
    }
    catch {
        Write-Error "Error writing to log file: $($_.Exception.Message)"
    }
}
