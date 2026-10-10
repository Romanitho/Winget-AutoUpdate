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

    # User and SYSTEM processes use separate logs. The SYSTEM audit log inherits
    # its protected installation-directory ACL and is never writable by users.
    $logDirectory = Split-Path -Parent $LogFile
    if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
    }

    $isSystemWriter = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
    if ($isSystemWriter -and -not $Script:WauLogAclChecked) {
        $acl = Get-Acl -LiteralPath $LogFile
        $authenticatedUsers = 'S-1-5-11'
        $changed = $false
        foreach ($rule in @($acl.Access)) {
            try { $ruleSid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
            if (-not $rule.IsInherited -and $ruleSid -eq $authenticatedUsers) {
                $acl.RemoveAccessRuleSpecific($rule)
                $changed = $true
            }
        }
        if ($changed) { Set-Acl -LiteralPath $LogFile -AclObject $acl }
        $Script:WauLogAclChecked = $true
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
