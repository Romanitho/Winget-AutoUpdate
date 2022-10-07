function Show-Toast ($Title, $Message, $MessageType, $Balise, $OnClickAction) {

	$ToastOnClickAction = "activationType='protocol' launch='$OnClickAction'"

	#Add XML variables
	[xml]$ToastTemplate = @"
<toast $ToastOnClickAction>
<visual>
    <binding template="ToastImageAndText03">
        <text id="1">$Title</text>
        <text id="2">$Message</text>
        <image id="1" src="$PSScriptRoot\icons\$MessageType.png" />
    </binding>
</visual>
<tag>$Balise</tag>
</toast>
"@
	#Load Assemblies
	[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
	[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

	#Prepare XML
	$ToastXml = [Windows.Data.Xml.Dom.XmlDocument]::New()
	$ToastXml.LoadXml($ToastTemplate.OuterXml)

	#Specify Launcher App ID
	$LauncherID = "Windows.SystemToast.Winget.Notification"

	#Prepare and Create Toast
	$ToastMessage = [Windows.UI.Notifications.ToastNotification]::New($ToastXml)
	$ToastMessage.Tag = $ToastTemplate.toast.tag
	[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($LauncherID).Show($ToastMessage)
}

$OnClickAction = "$PSScriptRoot\logs\updates.log"
$Title = "Winget-AutoUpdate (WAU)"
$Balise = "Winget-AutoUpdate (WAU)"

try {
	#Run scheduled task
	Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction Stop | Start-ScheduledTask -ErrorAction Stop
	#Send notification
	$Message = "Starting a manual check for updated apps..."
	$MessageType = "info"
	Show-Toast $Title $Message $MessageType $Balise $OnClickAction
}
catch {
	#Just send notification
	$Message = "Couldn't start a manual check for updated apps..."
	$MessageType = "error"
	Show-Toast $Title $Message $MessageType $Balise $OnClickAction
}
