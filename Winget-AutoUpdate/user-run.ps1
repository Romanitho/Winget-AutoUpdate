<#
.SYNOPSIS
Handle user interaction from shortcuts and show a Toast

.DESCRIPTION
Act on shortcut run (DEFAULT: Check for updated Apps)

.PARAMETER Logs
Open the Log file from Winget-AutoUpdate installation location

.PARAMETER Help
Open the Web Help page
https://github.com/Romanitho/Winget-AutoUpdate

.EXAMPLE
.\user-run.ps1 -Logs

#>

[CmdletBinding()]
param(
	[Parameter(Mandatory=$False)] [Switch] $Logs = $false,
	[Parameter(Mandatory=$False)] [Switch] $Help = $false
)

function Show-Toast ($Title, $Message, $MessageType, $Balise, $OnClickAction) {

	#Prepare OnClickAction (if set)
	if ($OnClickAction){
		$ToastOnClickAction = "activationType='protocol' launch='$OnClickAction'"
	}

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

Function Get-ToastLocale {
    
    #Get OS locale
    $OSLocale = (Get-Culture).Parent

    #Test if OS locale notif file exists
    $TestOSLocalPath = "$PSScriptRoot\locale\$($OSLocale.Name).xml"   
    
    #Set OS Local if file exists
    if (Test-Path $TestOSLocalPath) {
        $LocaleFile = $TestOSLocalPath
    }
    #Set English if file doesn't exist
    else {
        $LocaleFile = "$PSScriptRoot\locale\en.xml"
    }

	#Get locale XML file content
    [xml]$Script:ToastLocale = Get-Content $LocaleFile -Encoding UTF8 -ErrorAction SilentlyContinue

	#Test if strings exist in $LocaleFile
	if ($null -eq $ToastLocale.local.outputs.output[7].message){
		$LocaleFile = "$PSScriptRoot\locale\en.xml"
		#Get locale XML file content
		[xml]$Script:ToastLocale = Get-Content $LocaleFile -Encoding UTF8 -ErrorAction SilentlyContinue
	}
}

<# MAIN #>

#Get Toast Locale function
Get-ToastLocale

$OnClickAction = "$PSScriptRoot\logs\updates.log"
$Title = "Winget-AutoUpdate (WAU)"
$Balise = "Winget-AutoUpdate (WAU)"

if ($Logs) {
	if ((Test-Path "$PSScriptRoot\logs\updates.log")) {
		Invoke-Item "$PSScriptRoot\logs\updates.log"
	}
	else {
		$Message = $ToastLocale.local.outputs.output[5].message
		$MessageType = "warning"
		Show-Toast $Title $Message $MessageType $Balise
	}
}
elseif ($Help) {
	Start-Process "https://github.com/Romanitho/Winget-AutoUpdate"
}
else {
	try {
		#Run scheduled task
		Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction Stop | Start-ScheduledTask -ErrorAction Stop
		#Send notification
		$Message = $ToastLocale.local.outputs.output[6].message
		$MessageType = "info"
		Show-Toast $Title $Message $MessageType $Balise $OnClickAction
	}
	catch {
		#Just send notification
		$Message = $ToastLocale.local.outputs.output[7].message
		$MessageType = "error"
		Show-Toast $Title $Message $MessageType $Balise
	}
}
