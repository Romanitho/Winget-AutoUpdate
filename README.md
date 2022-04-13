
# Winget-AutoUpdate (WAU)
This project uses the Winget tool to daily update apps (with system context) and notify users when updates are available and installed.

![image](https://user-images.githubusercontent.com/96626929/150645599-9460def4-0818-4fe9-819c-dd7081ff8447.png)

## Intallation
Just [download latest version](https://github.com/Romanitho/Winget-AutoUpdate/archive/refs/tags/v1.7.3.zip), unzip, run "install.bat" as admin to install by default.

## Configurations
### Keep some apps out of Winget-AutoUpdate
- #### Black List
You can exclude apps from update job (for instance, apps you want to keep at a specific version or apps with built-in auto-update):
Add (or remove) the apps' ID you want to disable autoupdate to 'excluded_apps.txt'. (File must be placed in scripts' installation folder, or re-run install.bat).
- #### Or White List
From 1.7.0 version, you can update only pre-selected apps. To do so, create an "included_apps.txt" with the apps' ID of the apps you want to auto-update and run the `Winget-AutoUpdate-Install.ps1` with `-UseWhiteList` parameter. Related post: https://github.com/Romanitho/Winget-AutoUpdate/issues/36
### Default install location
By default, scripts and components will be placed in ProgramData location (inside a Winget-AutoUpdate folder). You can change this with script argument.
### Notification language
You can easily translate toast notifications by creating your locale xml config file (and share it with us :) ).
### When does the script run?
Scheduled task is set to run:
- At user logon
- At 6AM Everyday (with the -StartWhenAvailable option to be sure it is run at least once a day)
This way, even without connected user, powered on computers get updated anyway.
### Log location
You can find logs in install location, in log folder.
### "Unknown" App version
As explained in this [post](https://github.com/microsoft/winget-cli/issues/1255), Winget cannot detect the current version of some installed apps. We decided to skip managing these apps with WAU to avoid retries each time WAU runs:

![image](https://user-images.githubusercontent.com/96626929/155092000-c774979d-2db7-4dc6-8b7c-bd11c7643950.png)

Eventually, try to reinstall or update app manually to see if new version is detected.

## Update WAU
### Manual Update
Same process as new installation : download, unzip and run "install.bat".

### Automatic Update
A new Auto-Update process has been released from version 1.5.0. By default, WAU AutoUpdate is enabled. It will not overwrite the configurations, icons (if personalised), excluded_apps list,...
To disable WAU AutoUpdate, run the "winget-install-and-update.ps1" with "-DisableWAUAutoUpdate" parameter

## Advanced installation
You can run the `winget-install-and-update.ps1` script with parameters :

**-Silent**  
Install Winget-AutoUpdate and prerequisites silently

**-WingetUpdatePath**  
Specify Winget-AutoUpdate installation location. Default: `C:\ProgramData\Winget-AutoUpdate\` (Recommended to leave default)

**-DoNotUpdate**  
Do not run Winget-AutoUpdate after installation. By default, Winget-AutoUpdate is run just after installation.

**-DisableWAUAutoUpdate**  
Disable Winget-AutoUpdate update checking. By default, WAU auto updates if new version is available on Github.

**-UseWhiteList**  
Use White List instead of Black List. This setting will not create the "exclude_apps.txt" but "include_apps.txt"

**-Uninstall**  
Remove scheduled tasks and scripts.

## Help
In some cases, you need to "unblock" the "install.bat" file (Windows Defender SmartScreen). Right click, properties and unblock. Then, you'll be able to run it.

## Optimization
Feel free to give us any suggestions or optimizations in code.
