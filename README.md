# Winget-AutoUpdate
Scripts to create scheduled tasks to daily update apps as system and notify connected users.


![image](https://user-images.githubusercontent.com/96626929/150645599-9460def4-0818-4fe9-819c-dd7081ff8447.png)

## Intallation
Just download project, unzip, run install.bat as admin.

## Info
### Keep some apps out of Winget-AutoUpdate
You can exclude apps from update job (for instance, apps you want to keep at a specific version or apps with built-in auto-update):
Add the apps' ID you want to disable autoupdate to 'sample-excluded_apps.txt' and rename it to 'excluded_apps.txt'. (File must be placed in scripts' installation folder, or re-run install.bat).
### Default install location
By default, scripts and componants will be placed in ProgramData location (inside a Winget-autoupdate folder). You can change this with script argument.
### Notification language
You can easily translate toast notifications by creating your locale xml config file (and share it with us :) ).
### When does the script run?
Scheduled task is set to run:
- At user logon
- At 6AM eveyday (with the -StartWhenAvailable option to be sure it is run at least once a day)
This way, even without connected user, powered on computers get updated anyway.
### Log location
You can find logs in install location, in log folder.

## Optimization
As scripting is not my main job, feel free to give us any suggestions or optimizations in code.
