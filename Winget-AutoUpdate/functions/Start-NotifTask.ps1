#Function to send notifications to user

function Start-NotifTask ($Title,$Message,$MessageType,$Balise) {

    if (($NotificationLevel -eq "Full") -or ($NotificationLevel -eq "SuccessOnly" -and $MessageType -eq "Success")) {

        #Add XML variables
        [xml]$ToastTemplate = @"
<toast launch="ms-get-started://redirect?id=apps_action">
    <visual>
        <binding template="ToastImageAndText03">
            <text id="1">$Title</text>
            <text id="2">$Message</text>
            <image id="1" src="$WorkingDir\icons\$MessageType.png" />
        </binding>
    </visual>
    <tag>$Balise</tag>
</toast>
"@

        #Check if running account is system or interactive logon
        $currentPrincipal = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-4")
        
        #if not "Interactive" user, run as system
        if ($currentPrincipal -eq $false){

            #Save XML to File
            $ToastTemplateLocation = "$env:ProgramData\Winget-AutoUpdate\"
            if (!(Test-Path $ToastTemplateLocation)){
                New-Item -ItemType Directory -Force -Path $ToastTemplateLocation
            }
            $ToastTemplate.Save("$ToastTemplateLocation\config\notif.xml")

            #Run Notify scheduled task to notify conneted users
            Get-ScheduledTask -TaskName "Winget-AutoUpdate-Notify" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
        
        }
        #else, run as connected user
        else{

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