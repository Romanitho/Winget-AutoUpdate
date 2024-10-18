#Send Notify Script

#get xml notif config
$WAUinstalledPath = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\" -Name InstallLocation
[xml]$NotifConf = Get-Content "$WAUinstalledPath\config\notif.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
if (!($NotifConf)) {
    break
}

#Load Assemblies
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

#Prepare XML
$ToastXml = [Windows.Data.Xml.Dom.XmlDocument]::New()
$ToastXml.LoadXml($NotifConf.OuterXml)

#Specify Launcher App ID
$LauncherID = "Windows.SystemToast.WAU.Notification"

#Prepare and Create Toast
$ToastMessage = [Windows.UI.Notifications.ToastNotification]::New($ToastXML)
$ToastMessage.Tag = $NotifConf.toast.tag
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($LauncherID).Show($ToastMessage)
