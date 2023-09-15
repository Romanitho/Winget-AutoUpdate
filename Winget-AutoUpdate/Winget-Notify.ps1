# Send Notify Script

# get xml notif config
$WAUinstalledPath = (Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate\' -Name InstallLocation)
[xml]$NotifConf = (Get-Content -Path "$WAUinstalledPath\config\notif.xml" -Encoding UTF8 -ErrorAction SilentlyContinue)

if (!($NotifConf)) 
{
   break
}

# Load Assemblies
$null = (Add-Type -AssemblyName Windows.Data)
$null = (Add-Type -AssemblyName Windows.UI)

$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

# Prepare XML
$ToastXml = [Windows.Data.Xml.Dom.XmlDocument]::New()
$ToastXml.LoadXml($NotifConf.OuterXml)

# Specify Launcher App ID
$LauncherID = 'Windows.SystemToast.Winget.Notification'

# Prepare and Create Toast
$ToastMessage = [Windows.UI.Notifications.ToastNotification]::New($ToastXml)
$ToastMessage.Tag = $NotifConf.toast.tag
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($LauncherID).Show($ToastMessage)
