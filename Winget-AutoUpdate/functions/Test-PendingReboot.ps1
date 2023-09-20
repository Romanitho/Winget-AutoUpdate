# Function to check if there is a Pending Reboot

function Test-PendingReboot
{
   $Computer = $env:COMPUTERNAME
   $PendingReboot = $false

   $HKLM = [UInt32] '0x80000002'
   $WMI_Reg = [WMIClass] ('\\{0}\root\default:StdRegProv' -f $Computer)

   if ($WMI_Reg)
   {
      if (($WMI_Reg.EnumKey($HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\')).sNames -contains 'RebootPending')
      {
         $PendingReboot = $true
      }
      if (($WMI_Reg.EnumKey($HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\')).sNames -contains 'RebootRequired')
      {
         $PendingReboot = $true
      }

      # Checking for SCCM namespace
      $SCCM_Namespace = Get-WmiObject -Namespace ROOT\CCM\ClientSDK -List -ComputerName $Computer -ErrorAction Ignore
      if ($SCCM_Namespace)
      {
         if (([WmiClass]('\\{0}\ROOT\CCM\ClientSDK:CCM_ClientUtilities' -f $Computer)).DetermineIfRebootPending().RebootPending -eq $true)
         {
            $PendingReboot = $true
         }
      }
   }

   return $PendingReboot
}
