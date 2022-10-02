<#
.SYNOPSIS
Run the task Winget-AutoUpdate manually

.DESCRIPTION
If -Delta: Run under user context and get the delta between "system" apps and all apps (returned by user context command)

.PARAMETER Delta
Find user context installations

.EXAMPLE
.\user-start.ps1 -Delta

#>

<# APP ARGUMENTS #>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$False)] [Switch] $Delta = $false
)

#Run scheduled task
Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue

$OnClickAction = "$PSScriptRoot\logs\updates.log"
$ToastOnClickAction = "activationType='protocol' launch='$OnClickAction'"
$Title = "Winget-AutoUpdate (WAU)"
$Message = "Starting a manual check for updated apps..."
$MessageType = "info"
$Balise = "Winget-AutoUpdate (WAU)"

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

if ($Delta) {
    #Do the comparision...
}