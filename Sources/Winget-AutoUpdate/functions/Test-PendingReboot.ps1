<#
.SYNOPSIS
    Checks for pending Windows reboot.

.OUTPUTS
    Boolean: True if reboot pending.
#>
function Test-PendingReboot {

    $Computer = $env:COMPUTERNAME
    $HKLM = [UInt32]"0x80000002"
    $WMI = [WMIClass]"\\$Computer\root\default:StdRegProv"

    if (-not $WMI) { return $false }

    # Check CBS
    if (($WMI.EnumKey($HKLM, "SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\")).sNames -contains 'RebootPending') {
        return $true
    }

    # Check Windows Update
    if (($WMI.EnumKey($HKLM, "SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\")).sNames -contains 'RebootRequired') {
        return $true
    }

    # Check SCCM
    $SCCM = Get-WmiObject -Namespace ROOT\CCM\ClientSDK -List -ComputerName $Computer -ErrorAction Ignore
    if ($SCCM) {
        if (([WmiClass]"\\$Computer\ROOT\CCM\ClientSDK:CCM_ClientUtilities").DetermineIfRebootPending().RebootPending) {
            return $true
        }
    }

    return $false
}
