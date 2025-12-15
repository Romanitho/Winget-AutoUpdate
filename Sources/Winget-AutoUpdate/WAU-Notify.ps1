<#
.SYNOPSIS
    Displays a toast notification to the logged-in user.

.DESCRIPTION
    Reads notification configuration from an XML file and displays
    a Windows toast notification using the ToastNotificationManager API.
    This script is called by a scheduled task when WAU runs in system context.

.NOTES
    Configuration file: config\notif.xml
    Launcher ID: Windows.SystemToast.WAU.Notification
#>

# Get WAU installation path from registry
$WAUinstalledPath = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\" -Name InstallLocation

# Load notification XML configuration
[xml]$NotifConf = Get-Content "$WAUinstalledPath\config\notif.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
if (!($NotifConf)) {
    break
}

# Load Windows notification assemblies
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

# Parse notification XML
$ToastXml = [Windows.Data.Xml.Dom.XmlDocument]::New()
$ToastXml.LoadXml($NotifConf.OuterXml)

# Specify toast launcher ID
$LauncherID = "Windows.SystemToast.WAU.Notification"

# Create and display the notification
$ToastMessage = [Windows.UI.Notifications.ToastNotification]::New($ToastXML)
$ToastMessage.Tag = $NotifConf.toast.tag
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($LauncherID).Show($ToastMessage)
