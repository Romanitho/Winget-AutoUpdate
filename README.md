# Winget-AutoUpdate (WAU)
This project uses the Winget tool to daily update apps (with system context) and notify users when updates are available and installed.

![image](https://user-images.githubusercontent.com/96626929/150645599-9460def4-0818-4fe9-819c-dd7081ff8447.png)

## Intallation
Just [download latest release (source code)](https://github.com/Romanitho/Winget-AutoUpdate/releases), unzip, run "install.bat" as admin to install by default.

## Configurations
### Keep some apps out of Winget-AutoUpdate
- #### BlockList
You can exclude apps from update job (for instance, apps you want to keep at a specific version or apps with built-in auto-update):
Add (or remove) the apps' ID you want to disable autoupdate to 'excluded_apps.txt'. (File must be placed in WAU's installation folder, or re-run install.bat).
- #### Or AllowList
From 1.7.0 version, you can update only pre-selected apps. To do so, create an "included_apps.txt" with the apps' ID of the apps you want to auto-update and run the `Winget-AutoUpdate-Install.ps1` with `-UseWhiteList` parameter. Related post: https://github.com/Romanitho/Winget-AutoUpdate/issues/36

> You can use WiGui to create these lists: https://github.com/Romanitho/Winget-Install-GUI

### Notification Level
From version 1.9.0, you can choose which notification will be displayed: Full, Success only or none. Use `-NotificationLevel` parameter when you run `Winget-AutoUpdate-Install.ps1`

### Notification language
You can easily translate toast notifications by creating your locale xml config file (and share it with us :) ).

### Default install location
By default, scripts and components will be placed in ProgramData location (inside a Winget-AutoUpdate folder). You can change this with script argument (Not Recommended).

### When does the script run?
From version 1.9.0 (on new installations) WAU runs everyday at 6AM. You can now configure the frequency with `-UpdatesInterval` option (Daily, Weekly, Biweekly or Monthly). You can also add `-UpdatesAtLogon` parameter to run at user logon and keep this option activated like previous versions (recommanded).

### Log location
You can find logs in install location, in logs folder.

### "Unknown" App version
As explained in this [post](https://github.com/microsoft/winget-cli/issues/1255), Winget cannot detect the current version of some installed apps. We decided to skip managing these apps with WAU to avoid retries each time WAU runs:

![image](https://user-images.githubusercontent.com/96626929/155092000-c774979d-2db7-4dc6-8b7c-bd11c7643950.png)

Eventually, try to reinstall or update app manually to see if new version is detected.

### Handle metered connections

We might want to stop WAU on metered connection (to save cellular data on connection sharing for instance). That's why from v1.12.0 the default behavior will detect and stop WAU on limited connections (only for fresh install).

> Previous installed versions will ignore this new setting on update to keep historical operation.

To force WAU to run on metered connections anyway, run new installation with `-RunOnMetered` parameter.

### System & user context
From version 1.15.0, WAU run with system and user contexts. This way, even apps installed on User's scope are updated. Shorcuts for manually run can also be installed

## Update WAU
### Manual Update
Same process as new installation : download, unzip and run `install.bat`.

### Automatic Update
A new Auto-Update process has been released from version 1.5.0. By default, WAU AutoUpdate is enabled. It will not overwrite the configurations, icons (if personalised), excluded_apps list,...
To disable WAU AutoUpdate, run the `winget-install-and-update.ps1` with `-DisableWAUAutoUpdate` parameter

## Uninstall WAU
Simply uninstall it from your programs:  

![image](https://user-images.githubusercontent.com/96626929/170879336-ef034956-4778-41f0-b8fd-d307b77b70a9.png)

## GUI installation
[WiGui](https://github.com/Romanitho/Winget-Install-GUI/) can be used to install WAU even easier:  

<img src="https://user-images.githubusercontent.com/96626929/167912772-de5a55fe-68a8-44ed-91fb-fcf5b34d891f.png" width="400">

## Advanced installation
You can run the `Winget-AutoUpdate-Install.ps1` script with parameters :

**-Silent**  
Install Winget-AutoUpdate and prerequisites silently

**-WingetUpdatePath**  
Specify Winget-AutoUpdate installation location. Default: `C:\ProgramData\Winget-AutoUpdate` (Recommended to leave default)

**-DoNotUpdate**  
Do not run Winget-AutoUpdate after installation. By default, Winget-AutoUpdate is run just after installation.

**-DisableWAUAutoUpdate**  
Disable Winget-AutoUpdate update checking. By default, WAU auto updates if new version is available on Github.

**-UseWhiteList**  
Use White List instead of Black List. This setting will not create the "excluded_apps.txt" but "included_apps.txt"

**-ListPath**  
Get Black/White List from Path (URL/UNC/Local) (download/copy to Winget-AutoUpdate installation location if external list is newer).

**-ModsPath**  
Get Mods from Path (URL/UNC/Local) (download/copy to `mods` in Winget-AutoUpdate installation location if external mods is newer).  
For URL: This requires a site with `Options +Indexes` in `.htaccess` and no index page overriding the listing of files.  
Or an index page with href listings of all the Mods to be downloaded (with a first link to skip, emulating a directory list):  
```
<ul><li><a  href="/wau/"> Parent Directory</a></li>
<li><a  href="Adobe.Acrobat.Reader.32-bit-install.ps1"> Adobe.Acrobat.Reader.32-bit-install.ps1</a></li>
<li><a  href="Notepad++.Notepad++-install.ps1"> Notepad++.Notepad++-install.ps1</a></li>
<li><a  href="Notepad++.Notepad++-uninstall.ps1"> Notepad++.Notepad++-uninstall.ps1</a></li>
<li><a  href="WinMerge.WinMerge-install.ps1"> WinMerge.WinMerge-install.ps1</a></li>
</ul>
```

**-InstallUserContext**  
Install WAU with system and **user** context executions (From version 1.15.3)

**-BypassListForUsers**  
Bypass Black/White list when run in user context (From version 1.15.0)

**-NoClean**  
Keep critical files when installing/uninstalling. This setting will keep "excluded_apps.txt", "included_apps.txt", "mods" and "logs" as they were.

**-DesktopShortcut**  
Create a shortcut for user interaction on the Desktop to run task `Winget-AutoUpdate` (From version 1.15.0)

**-StartMenuShortcut**  
Create shortcuts for user interaction in the Start Menu to run task `Winget-AutoUpdate`, open Logs and Web Help (From version 1.15.0)

**-NotificationLevel**  
Specify the Notification level: Full (Default, displays all notification), SuccessOnly (Only displays notification for success) or None (Does not show any popup).

**-UpdatesAtLogon**  
Set WAU to run at user logon.

**-UpdatesInterval**  
Specify the update frequency: Daily (Default), Weekly, Biweekly, Monthly or Never. Can be set to 'Never' in combination with '-UpdatesAtLogon' for instance

**-UpdatesAtTime**  
Specify the time of the update interval execution time. Default 6AM. (From version 1.15.0)

**-RunOnMetered**  
Run WAU on metered connection. Default No.

**-Uninstall**  
Remove scheduled tasks and scripts.

## Intune/SCCM use
See https://github.com/Romanitho/Winget-AutoUpdate/discussions/88

## Custom scripts (Mods feature)
From version 1.8.0, the Mods feature allows you to run an additional script when upgrading or installing an app.
Just put the script in question with the App ID followed by the `-upgrade` or `-install` suffix in the "mods" folder.
WAU will call `AppID-upgrade.ps1` and/or `AppID-install.ps1` (if they differs, otherwise the "-install" mod will be used for upgrades too) if it exists in the "mods" folder just after the upgrade/install.

> Example:
If you want to run a script that removes the shortcut from "%PUBLIC%\Desktop" (we don't want to fill the desktop with shortcuts our users can't delete) just after installing "Acrobat Reader DC" (32-bit), prepare a powershell script that removes the Public Desktop shortcut "Acrobat Reader DC.lnk" and name your script like this:
`Adobe.Acrobat.Reader.32-bit-install.ps1` and put it in the "mods" folder.

You can find more information on Winget-Install Repo, as it's a related feature

## Help
In some cases, you need to "unblock" the `install.bat` file (Windows Defender SmartScreen). Right click, properties and unblock. Then, you'll be able to run it.

## Known issues
* As reported by [soredake](https://github.com/soredake), Powershell from MsStore is not supported with WAU in system context. See https://github.com/Romanitho/Winget-AutoUpdate/issues/113

## Optimization
Feel free to give us any suggestions or optimizations in code and support us by adding a star :)
