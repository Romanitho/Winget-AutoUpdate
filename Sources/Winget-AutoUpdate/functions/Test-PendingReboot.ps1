#Function to check if there is a Pending Reboot

function Test-PendingReboot {

    $Computer = $env:COMPUTERNAME
    $PendingReboot = $false

    $HKLM = [UInt32] "0x80000002"
    $WMI_Reg = [WMIClass] "\\$Computer\root\default:StdRegProv"

    if ($WMI_Reg) {
        if (($WMI_Reg.EnumKey($HKLM, "SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\")).sNames -contains 'RebootPending') { $PendingReboot = $true }
        if (($WMI_Reg.EnumKey($HKLM, "SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\")).sNames -contains 'RebootRequired') { $PendingReboot = $true }

        #Checking for SCCM namespace (can't get it done with Get-CimInstance, using deprecated Get-WmiObject)
        $SCCM_Namespace = Get-WmiObject -Namespace ROOT\CCM\ClientSDK -List -ComputerName $Computer -ErrorAction Ignore
        if ($SCCM_Namespace) {
            if (([WmiClass]"\\$Computer\ROOT\CCM\ClientSDK:CCM_ClientUtilities").DetermineIfRebootPending().RebootPending -eq $true) { $PendingReboot = $true }
        }

    }

    return $PendingReboot

}
