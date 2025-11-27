<#
.SYNOPSIS
    Writes a timestamped message to console and log file.

.PARAMETER LogMsg
    Message to log.

.PARAMETER LogColor
    Console color (default: White).

.PARAMETER IsHeader
    Format as section header.
#>
function Write-ToLog {
    [CmdletBinding()]
    param(
        [String]$LogMsg,
        [String]$LogColor = "White",
        [Switch]$IsHeader
    )

    # Create log file with proper ACL if needed
    if (!(Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
        $acl = Get-Acl $LogFile
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11")),
            "Modify", "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl $LogFile $acl
    }

    # Format log entry
    $Log = if ($IsHeader) {
        $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
        "#" * 65 + "`n#    $date - $LogMsg`n" + "#" * 65
    }
    else {
        "$(Get-Date -UFormat '%T') - $LogMsg"
    }

    Write-Host $Log -ForegroundColor $LogColor
    $Log | Out-File -FilePath $LogFile -Append
}
