[System.Diagnostics.EventLog]::WriteEntry("Winget-AutoUpdate (WAU)", "Winget-AutoUpdate (WAU) started by user shortcut.", "Information", 100)

$Title = "Winget-AutoUpdate (WAU)"
$Message = "Starting a manual check for updated apps..."

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

$APP_ID = 'Windows.SystemToast.Winget.Notification'

$template = @"
<toast>
    <visual>
        <binding template="ToastImageAndText03">
            <text id="1">$($Title)</text>
            <text id="2">$($Message)</text>0
            <image id="1" src="$PSScriptRoot\icons\info.png" />
        </binding>
    </visual>
</toast>
"@

$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml($template)
$toast = New-Object Windows.UI.Notifications.ToastNotification $xml
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($APP_ID).Show($toast)
