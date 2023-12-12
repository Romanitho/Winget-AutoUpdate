#Function to send the notifications to user

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

    if (($WAUConfig.WAU_NotificationLevel -eq "Full") -or ($WAUConfig.WAU_NotificationLevel -eq "SuccessOnly" -and $MessageType -eq "Success") -or ($UserRun)) {

        # XML Toast template creation
        [xml]$ToastTemplate = New-Object system.Xml.XmlDocument
        $ToastTemplate.LoadXml("<?xml version=`"1.0`" encoding=`"utf-8`"?><toast></toast>")

        # Creation of visual node
        $XMLvisual = $ToastTemplate.CreateElement("visual")

        # Creation of a binding node
        $XMLbinding = $ToastTemplate.CreateElement("binding")
        $XMLvisual.AppendChild($XMLbinding) | Out-Null
        $XMLbindingAtt1 = ($ToastTemplate.CreateAttribute("template"))
        $XMLbindingAtt1.Value = "ToastGeneric"
        $XMLbinding.Attributes.Append($XMLbindingAtt1) | Out-Null

        $XMLimagepath = "$WorkingDir\icons\$MessageType.png"
        if (Test-Path $XMLimagepath) {
            # Creation of an image node
            $XMLimage = $ToastTemplate.CreateElement("image")
            $XMLbinding.AppendChild($XMLimage) | Out-Null
            $XMLimageAtt1 = $ToastTemplate.CreateAttribute("placement")
            $XMLimageAtt1.Value = "appLogoOverride"
            $XMLimage.Attributes.Append($XMLimageAtt1) | Out-Null
            $XMLimageAtt2 = $ToastTemplate.CreateAttribute("src")
            $XMLimageAtt2.Value = "$WorkingDir\icons\$MessageType.png"
            $XMLimage.Attributes.Append($XMLimageAtt2) | Out-Null
        }

        if ($Title) {
            # Creation of a text node
            $XMLtitle = $ToastTemplate.CreateElement("text")
            $XMLtitleText = $ToastTemplate.CreateTextNode($Title)
            $XMLtitle.AppendChild($XMLtitleText) | Out-Null
            $XMLbinding.AppendChild($XMLtitle) | Out-Null
        }

        if ($Message) {
            # Creation of a text node
            $XMLtext = $ToastTemplate.CreateElement("text")
            $XMLtextText = $ToastTemplate.CreateTextNode($Message)
            $XMLtext.AppendChild($XMLtextText) | Out-Null
            $XMLbinding.AppendChild($XMLtext) | Out-Null
        }

        if ($Body) {
            # Creation of a group node
            $XMLgroup = $ToastTemplate.CreateElement("group")
            $XMLbinding.AppendChild($XMLgroup) | Out-Null

            # Creation of a subgroup node
            $XMLsubgroup = $ToastTemplate.CreateElement("subgroup")
            $XMLgroup.AppendChild($XMLsubgroup) | Out-Null

            # Creation of a text node
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

        # Creation of actions node
        $XMLactions = $ToastTemplate.CreateElement("actions")

        if ($Button1Text) {
            # Creation of action node
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

        if ($ButtonDismiss) {
            # Creation of action node
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

        # Creation of tag node
        $XMLtag = $ToastTemplate.CreateElement("tag")
        $XMLtagText = $ToastTemplate.CreateTextNode($Balise)
        $XMLtag.AppendChild($XMLtagText) | Out-Null

        # Add the visual node to the xml
        $ToastTemplate.LastChild.AppendChild($XMLvisual) | Out-Null
        $ToastTemplate.LastChild.AppendChild($XMLactions) | Out-Null
        $ToastTemplate.LastChild.AppendChild($XMLtag) | Out-Null

        if ($OnClickAction) {
            $ToastTemplate.toast.SetAttribute("activationType", "Protocol") | Out-Null
            $ToastTemplate.toast.SetAttribute("launch", $OnClickAction) | Out-Null
        }

        #if running as System, run Winget-AutoUpdate-Notify scheduled task
        if ($IsSystem) {

            #Save XML to File
            $ToastTemplateLocation = "$($WAUConfig.InstallLocation)\config\"
            if (!(Test-Path $ToastTemplateLocation)) {
                New-Item -ItemType Directory -Force -Path $ToastTemplateLocation
            }
            $ToastTemplate.Save("$ToastTemplateLocation\notif.xml")

            #Run Notify scheduled task to notify conneted users
            Get-ScheduledTask -TaskName "Winget-AutoUpdate-Notify" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue

        }
        #else, run as connected user
        else {

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

        #Wait for notification to display
        Start-Sleep 3

    }

}
