<#
.SYNOPSIS
    Displays a Windows toast notification to the user.

.DESCRIPTION
    Creates and displays a Windows toast notification with customizable
    title, message, icon, and action buttons. Handles both system context
    (via scheduled task) and user context (direct notification).

.PARAMETER Title
    The notification title. Defaults to "Winget-AutoUpdate".

.PARAMETER Message
    The main notification message text.

.PARAMETER MessageType
    The notification type (info, success, warning, error).
    Determines the icon displayed.

.PARAMETER Balise
    Unique tag for the notification (for replacement logic).

.PARAMETER OnClickAction
    URL or action to execute when notification is clicked.

.PARAMETER Body
    Optional body text displayed below the message.

.PARAMETER Button1Text
    Text for the primary action button.

.PARAMETER Button1Action
    URL or action for the primary button.

.PARAMETER ButtonDismiss
    When specified, adds a dismiss button.

.PARAMETER UserRun
    When specified, forces notification display regardless of notification level.

.EXAMPLE
    Start-NotifTask -Title "Update Available" -Message "Firefox update ready" -MessageType "info"

.NOTES
    Respects WAU_NotificationLevel setting (Full, SuccessOnly, ErrorsOnly, None).
    In system context, saves notification to XML and triggers scheduled task.
#>
function Start-NotifTask {

    param(
        [String]$Title = "Winget-AutoUpdate",
        [String]$Message,
        [String]$MessageType,
        [String]$Balise = "WAU",
        [String]$OnClickAction,
        [String]$Body,
        [String]$Button1Text,
        [String]$Button1Action,
        [Switch]$ButtonDismiss = $false,
        [Switch]$UserRun = $false
    )

    # Check if notification should be displayed based on notification level settings
    if (($WAUConfig.WAU_NotificationLevel -eq "Full") -or ($WAUConfig.WAU_NotificationLevel -eq "SuccessOnly" -and $MessageType -eq "Success") -or ($WAUConfig.WAU_NotificationLevel -eq "ErrorsOnly" -and $MessageType -eq "Error") -or ($UserRun)) {

        # Create base XML toast template
        [xml]$ToastTemplate = New-Object system.Xml.XmlDocument
        $ToastTemplate.LoadXml("<?xml version=`"1.0`" encoding=`"utf-8`"?><toast></toast>")

        # Create visual container node
        $XMLvisual = $ToastTemplate.CreateElement("visual")

        # Create binding node with generic template
        $XMLbinding = $ToastTemplate.CreateElement("binding")
        $XMLvisual.AppendChild($XMLbinding) | Out-Null
        $XMLbindingAtt1 = ($ToastTemplate.CreateAttribute("template"))
        $XMLbindingAtt1.Value = "ToastGeneric"
        $XMLbinding.Attributes.Append($XMLbindingAtt1) | Out-Null

        # Add icon image if available
        $XMLimagepath = "$WorkingDir\icons\$MessageType.png"
        if (Test-Path $XMLimagepath) {
            $XMLimage = $ToastTemplate.CreateElement("image")
            $XMLbinding.AppendChild($XMLimage) | Out-Null
            $XMLimageAtt1 = $ToastTemplate.CreateAttribute("placement")
            $XMLimageAtt1.Value = "appLogoOverride"
            $XMLimage.Attributes.Append($XMLimageAtt1) | Out-Null
            $XMLimageAtt2 = $ToastTemplate.CreateAttribute("src")
            $XMLimageAtt2.Value = "$WorkingDir\icons\$MessageType.png"
            $XMLimage.Attributes.Append($XMLimageAtt2) | Out-Null
        }

        # Add title text if provided
        if ($Title) {
            $XMLtitle = $ToastTemplate.CreateElement("text")
            $XMLtitleText = $ToastTemplate.CreateTextNode($Title)
            $XMLtitle.AppendChild($XMLtitleText) | Out-Null
            $XMLbinding.AppendChild($XMLtitle) | Out-Null
        }

        # Add message text if provided
        if ($Message) {
            $XMLtext = $ToastTemplate.CreateElement("text")
            $XMLtextText = $ToastTemplate.CreateTextNode($Message)
            $XMLtext.AppendChild($XMLtextText) | Out-Null
            $XMLbinding.AppendChild($XMLtext) | Out-Null
        }

        # Add body text in a group/subgroup structure if provided
        if ($Body) {
            $XMLgroup = $ToastTemplate.CreateElement("group")
            $XMLbinding.AppendChild($XMLgroup) | Out-Null

            $XMLsubgroup = $ToastTemplate.CreateElement("subgroup")
            $XMLgroup.AppendChild($XMLsubgroup) | Out-Null

            $XMLcontent = $ToastTemplate.CreateElement("text")
            $XMLcontentText = $ToastTemplate.CreateTextNode($Body)
            $XMLcontent.AppendChild($XMLcontentText) | Out-Null
            $XMLsubgroup.AppendChild($XMLcontent) | Out-Null
            $XMLcontentAtt1 = $ToastTemplate.CreateAttribute("hint-style")
            $XMLcontentAtt1.Value = "body"
            $XMLcontent.Attributes.Append($XMLcontentAtt1) | Out-Null
            $XMLcontentAtt2 = $ToastTemplate.CreateAttribute("hint-wrap")
            $XMLcontentAtt2.Value = "true"
            $XMLcontent.Attributes.Append($XMLcontentAtt2) | Out-Null
        }

        # Create actions container for buttons
        $XMLactions = $ToastTemplate.CreateElement("actions")

        # Add primary button if text is provided
        if ($Button1Text) {
            $XMLaction = $ToastTemplate.CreateElement("action")
            $XMLactions.AppendChild($XMLaction) | Out-Null
            $XMLactionAtt1 = $ToastTemplate.CreateAttribute("content")
            $XMLactionAtt1.Value = $Button1Text
            $XMLaction.Attributes.Append($XMLactionAtt1) | Out-Null
            if ($Button1Action) {
                $XMLactionAtt2 = $ToastTemplate.CreateAttribute("arguments")
                $XMLactionAtt2.Value = $Button1Action
                $XMLaction.Attributes.Append($XMLactionAtt2) | Out-Null
                $XMLactionAtt3 = $ToastTemplate.CreateAttribute("activationType")
                $XMLactionAtt3.Value = "Protocol"
                $XMLaction.Attributes.Append($XMLactionAtt3) | Out-Null
            }
        }

        # Add dismiss button if requested
        if ($ButtonDismiss) {
            $XMLaction = $ToastTemplate.CreateElement("action")
            $XMLactions.AppendChild($XMLaction) | Out-Null
            $XMLactionAtt1 = $ToastTemplate.CreateAttribute("content")
            $XMLactionAtt1.Value = ""
            $XMLaction.Attributes.Append($XMLactionAtt1) | Out-Null
            $XMLactionAtt2 = $ToastTemplate.CreateAttribute("arguments")
            $XMLactionAtt2.Value = "dismiss"
            $XMLaction.Attributes.Append($XMLactionAtt2) | Out-Null
            $XMLactionAtt3 = $ToastTemplate.CreateAttribute("activationType")
            $XMLactionAtt3.Value = "system"
            $XMLaction.Attributes.Append($XMLactionAtt3) | Out-Null
        }

        # Add tag for notification identification/replacement
        $XMLtag = $ToastTemplate.CreateElement("tag")
        $XMLtagText = $ToastTemplate.CreateTextNode($Balise)
        $XMLtag.AppendChild($XMLtagText) | Out-Null

        # Assemble the XML structure
        $ToastTemplate.LastChild.AppendChild($XMLvisual) | Out-Null
        $ToastTemplate.LastChild.AppendChild($XMLactions) | Out-Null
        $ToastTemplate.LastChild.AppendChild($XMLtag) | Out-Null

        # Add click action if provided
        if ($OnClickAction) {
            $ToastTemplate.toast.SetAttribute("activationType", "Protocol") | Out-Null
            $ToastTemplate.toast.SetAttribute("launch", $OnClickAction) | Out-Null
        }

        # Display notification based on execution context
        if ($IsSystem) {
            # System context: Save XML and trigger notification task
            $ToastTemplateLocation = "$($WAUConfig.InstallLocation)\config\"
            $ToastTemplate.Save("$ToastTemplateLocation\notif.xml")

            # Run scheduled task to display notification to logged-in users
            Get-ScheduledTask -TaskName "Winget-AutoUpdate-Notify" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
        }
        else {
            # User context: Display notification directly
            [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
            [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

            $ToastXml = [Windows.Data.Xml.Dom.XmlDocument]::New()
            $ToastXml.LoadXml($ToastTemplate.OuterXml)

            $LauncherID = "Windows.SystemToast.WAU.Notification"

            $ToastMessage = [Windows.UI.Notifications.ToastNotification]::New($ToastXml)
            $ToastMessage.Tag = $ToastTemplate.toast.tag
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($LauncherID).Show($ToastMessage)
        }

        # Wait for notification to display
        Start-Sleep 3

    }

}
