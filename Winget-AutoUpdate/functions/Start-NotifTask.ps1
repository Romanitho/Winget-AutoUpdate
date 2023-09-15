# Function to send the notifications to user

function Start-NotifTask 
{
   [CmdletBinding()]
   param(
      [String]$Title = 'Winget-AutoUpdate',
      [String]$Message,
      [String]$MessageType,
      [String]$Balise = 'WAU',
      [String]$OnClickAction,
      [String]$Body,
      [String]$Button1Text,
      [String]$Button1Action,
      [Switch]$ButtonDismiss = $false,
      [Switch]$UserRun = $false
   )

   if (($WAUConfig.WAU_NotificationLevel -eq 'Full') -or ($WAUConfig.WAU_NotificationLevel -eq 'SuccessOnly' -and $MessageType -eq 'Success') -or ($UserRun)) 
   {
      # XML Toast template creation
      [xml]$ToastTemplate = New-Object -TypeName system.Xml.XmlDocument
      $ToastTemplate.LoadXml("<?xml version=`"1.0`" encoding=`"utf-8`"?><toast></toast>")

      # Creation of visual node
      $XMLvisual = $ToastTemplate.CreateElement('visual')

      # Creation of a binding node
      $XMLbinding = $ToastTemplate.CreateElement('binding')
      $null = $XMLvisual.AppendChild($XMLbinding)
      $XMLbindingAtt1 = ($ToastTemplate.CreateAttribute('template'))
      $XMLbindingAtt1.Value = 'ToastGeneric'
      $null = $XMLbinding.Attributes.Append($XMLbindingAtt1)

      $XMLimagepath = ('{0}\icons\{1}.png' -f $WorkingDir, $MessageType)
      if (Test-Path -Path $XMLimagepath -ErrorAction SilentlyContinue) 
      {
         # Creation of a image node
         $XMLimage = $ToastTemplate.CreateElement('image')
         $null = $XMLbinding.AppendChild($XMLimage)
         $XMLimageAtt1 = $ToastTemplate.CreateAttribute('placement')
         $XMLimageAtt1.Value = 'appLogoOverride'
         $null = $XMLimage.Attributes.Append($XMLimageAtt1)
         $XMLimageAtt2 = $ToastTemplate.CreateAttribute('src')
         $XMLimageAtt2.Value = ('{0}\icons\{1}.png' -f $WorkingDir, $MessageType)
         $null = $XMLimage.Attributes.Append($XMLimageAtt2)
      }

      if ($Title) 
      {
         # Creation of a text node
         $XMLtitle = $ToastTemplate.CreateElement('text')
         $XMLtitleText = $ToastTemplate.CreateTextNode($Title)
         $null = $XMLtitle.AppendChild($XMLtitleText)
         $null = $XMLbinding.AppendChild($XMLtitle)
      }

      if ($Message) 
      {
         # Creation of a text node
         $XMLtext = $ToastTemplate.CreateElement('text')
         $XMLtextText = $ToastTemplate.CreateTextNode($Message)
         $null = $XMLtext.AppendChild($XMLtextText)
         $null = $XMLbinding.AppendChild($XMLtext)
      }

      if ($Body) 
      {
         # Creation of a group node
         $XMLgroup = $ToastTemplate.CreateElement('group')
         $null = $XMLbinding.AppendChild($XMLgroup)

         # Creation of a subgroup node
         $XMLsubgroup = $ToastTemplate.CreateElement('subgroup')
         $null = $XMLgroup.AppendChild($XMLsubgroup)

         # Creation of a text node
         $XMLcontent = $ToastTemplate.CreateElement('text')
         $XMLcontentText = $ToastTemplate.CreateTextNode($Body)
         $null = $XMLcontent.AppendChild($XMLcontentText)
         $null = $XMLsubgroup.AppendChild($XMLcontent)
         $XMLcontentAtt1 = $ToastTemplate.CreateAttribute('hint-style')
         $XMLcontentAtt1.Value = 'body'
         $null = $XMLcontent.Attributes.Append($XMLcontentAtt1)
         $XMLcontentAtt2 = $ToastTemplate.CreateAttribute('hint-wrap')
         $XMLcontentAtt2.Value = 'true'
         $null = $XMLcontent.Attributes.Append($XMLcontentAtt2)
      }

      # Creation of actions node
      $XMLactions = $ToastTemplate.CreateElement('actions')

      if ($Button1Text) 
      {
         # Creation of action node
         $XMLaction = $ToastTemplate.CreateElement('action')
         $null = $XMLactions.AppendChild($XMLaction)
         $XMLactionAtt1 = $ToastTemplate.CreateAttribute('content')
         $XMLactionAtt1.Value = $Button1Text
         $null = $XMLaction.Attributes.Append($XMLactionAtt1)
         if ($Button1Action) 
         {
            $XMLactionAtt2 = $ToastTemplate.CreateAttribute('arguments')
            $XMLactionAtt2.Value = $Button1Action
            $null = $XMLaction.Attributes.Append($XMLactionAtt2)
            $XMLactionAtt3 = $ToastTemplate.CreateAttribute('activationType')
            $XMLactionAtt3.Value = 'Protocol'
            $null = $XMLaction.Attributes.Append($XMLactionAtt3)
         }
      }

      if ($ButtonDismiss) 
      {
         # Creation of action node
         $XMLaction = $ToastTemplate.CreateElement('action')
         $null = $XMLactions.AppendChild($XMLaction)
         $XMLactionAtt1 = $ToastTemplate.CreateAttribute('content')
         $XMLactionAtt1.Value = ''
         $null = $XMLaction.Attributes.Append($XMLactionAtt1)
         $XMLactionAtt2 = $ToastTemplate.CreateAttribute('arguments')
         $XMLactionAtt2.Value = 'dismiss'
         $null = $XMLaction.Attributes.Append($XMLactionAtt2)
         $XMLactionAtt3 = $ToastTemplate.CreateAttribute('activationType')
         $XMLactionAtt3.Value = 'system'
         $null = $XMLaction.Attributes.Append($XMLactionAtt3)
      }

      # Creation of tag node
      $XMLtag = $ToastTemplate.CreateElement('tag')
      $XMLtagText = $ToastTemplate.CreateTextNode($Balise)
      $null = $XMLtag.AppendChild($XMLtagText)

      # Add the visual node to the xml
      $null = $ToastTemplate.LastChild.AppendChild($XMLvisual)
      $null = $ToastTemplate.LastChild.AppendChild($XMLactions)
      $null = $ToastTemplate.LastChild.AppendChild($XMLtag)

      if ($OnClickAction) 
      {
         $null = $ToastTemplate.toast.SetAttribute('activationType', 'Protocol')
         $null = $ToastTemplate.toast.SetAttribute('launch', $OnClickAction)
      }

      # if not "Interactive" user, run as system
      if ($IsSystem) 
      {
         # Save XML to File
         $ToastTemplateLocation = ('{0}\config\' -f $WAUConfig.InstallLocation)
         if (!(Test-Path -Path $ToastTemplateLocation -ErrorAction SilentlyContinue)) 
         {
            $null = (New-Item -ItemType Directory -Force -Confirm:$false -Path $ToastTemplateLocation)
         }
            
         $ToastTemplate.Save(('{0}\notif.xml' -f $ToastTemplateLocation))

         # Run Notify scheduled task to notify conneted users
         $null = (Get-ScheduledTask -TaskName 'Winget-AutoUpdate-Notify' -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue)
      }
      else 
      {
         #else, run as connected user
         # Load Assemblies
         $null = (Add-Type -AssemblyName Windows.UI)
         $null = (Add-Type -AssemblyName Windows.Data)
         $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
         $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

         # Prepare XML
         $ToastXml = [Windows.Data.Xml.Dom.XmlDocument]::New()
         $ToastXml.LoadXml($ToastTemplate.OuterXml)

         # Specify Launcher App ID
         $LauncherID = 'Windows.SystemToast.Winget.Notification'

         # Prepare and Create Toast
         $ToastMessage = [Windows.UI.Notifications.ToastNotification]::New($ToastXml)
         $ToastMessage.Tag = $ToastTemplate.toast.tag
         [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($LauncherID).Show($ToastMessage)
      }

      # Wait for notification to display
      Start-Sleep -Seconds 3
   }
}
