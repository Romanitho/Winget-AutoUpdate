# Winget-Install

## Mods

The Mod feature allows you to run an additional script when installing or upgrading an app.
Just put the script with the App ID followed by the "-install" or "-upgrade" suffix to be considered.  
`AppID-install.ps1` and/or `AppID-upgrade.ps1` (if it differs, otherwise the "-install" mod will be used for upgrade)
and put this in the Mods directory  
> Example:  
> If you want to run a script just after installing ".NET Desktop Runtime 6", call your script like this:
> `Microsoft.dotnetRuntime.6-x64-install.ps1`

In the case of ".NET Desktop Runtime 6" it spawns a new process and this we will have to wait for completion of before moving on to checking if the installation/upgrade suceeded or not. - (this seems to be handled in Winget Version: v1.3.0-preview)
