<div align="center">

![image](https://github.com/Romanitho/Winget-AutoUpdate/assets/96626929/0e738c7a-cbe4-4010-94f6-1e9165bc0d49)

[![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/Romanitho/Winget-AutoUpdate?label=Latest%20Stable%20Release&style=for-the-badge)](https://github.com/Romanitho/Winget-AutoUpdate/releases/latest)

</div>

---

This project uses the Winget tool to daily update apps (with system context) and notify users when updates are available and installed.

![image](https://user-images.githubusercontent.com/96626929/150645599-9460def4-0818-4fe9-819c-dd7081ff8447.png)

## Installation
Just download latest release [WAU.msi](https://github.com/Romanitho/Winget-AutoUpdate/releases/latest):

![1](https://github.com/user-attachments/assets/8a3a656d-f825-4cea-b971-5f775a6c7ba8)
![2](https://github.com/user-attachments/assets/46913e03-8604-43f5-8bca-129d1e714e45)




## Configurations
### Keep some apps out of Winget-AutoUpdate
- #### BlockList
You can exclude apps from update job (for instance, apps you want to keep at a specific version or apps with built-in auto-update):
Add (or remove) the apps' ID you want to disable autoupdate to 'excluded_apps.txt'. (File must be placed in the same folder as WAU.msi).
- #### AllowList
You can update only pre-selected apps. To do so, create an "included_apps.txt" with the apps' ID of the apps you want to auto-update and place it in the same folder as WAU.msi during install.

> The lists can contain Wildcard (*). For instance ```Mozilla.Firefox*``` will take care of all Firefox channels.

### Notification Level
You can choose which notification will be displayed: `Full`, `Success only` or `None`.

### Notification language
You can easily translate toast notifications by creating your locale xml config file (and share it with us :) ).

### When does the script run?
WAU runs ,by default, at logon. You can configure the frequency with options (Daily, BiDaily, Weekly, BiWeekly, Monthly or Never).

### Log location
You can find logs in install location, in logs folder.<br>
If **Intune Management Extension** is installed, a **SymLink** (WAU-updates.log) is created under **C:\ProgramData\Microsoft\IntuneManagementExtension\Logs**<br>
If you are deploying winget Apps with [Winget-Install](https://github.com/Romanitho/Winget-Install) a **SymLink** (WAU-install.log) is also created under **C:\ProgramData\Microsoft\IntuneManagementExtension\Logs**

### "Unknown" App version
As explained in this [post](https://github.com/microsoft/winget-cli/issues/1255), Winget cannot detect the current version of some installed apps. We decided to skip managing these apps with WAU to avoid retries each time WAU runs:

![image](https://user-images.githubusercontent.com/96626929/155092000-c774979d-2db7-4dc6-8b7c-bd11c7643950.png)

Eventually, try to reinstall or update app manually to see if new version is detected.

### Handle metered connections

We might want to stop WAU on metered connection (to save cellular data on connection sharing for instance). The default behavior will detect and stop WAU on limited connections (only for fresh install).

To force WAU to run on metered connections anyway, run new installation with `-RunOnMetered` parameter.

### System & user context
WAU runs with system and user contexts. This way, even apps installed on User's scope are updated. Shorcuts for manually run can also be installed.

### Default install location
By default, scripts and components will be placed in "Program Files" location (inside a Winget-AutoUpdate folder).

## Update WAU
### Manual Update
Same process as new installation.

### Automatic Update
By default, WAU AutoUpdate is enabled. It will not overwrite the configurations, excluded_apps list,...

## Advanced installation
**Mainly for admins or advanced user installation.**<br>
You can run the `WAU.msi` script with parameters :

**/qn**<br>
Install Winget-AutoUpdate and prerequisites silently.

**RUN_WAU**<br>
Default value NO. Set `RUN_WAU=YES` to run WAU just after installation.

**DISABLEWAUAUTOUPDATE**<br>
Default value 0. Set `DISABLEWAUAUTOUPDATE=1` to disable Winget-AutoUpdate self update checking. By default, WAU auto updates if new version is available on Github.

**USEWHITELIST**<br>
Set `USEWHITELIST=1` to force WAU to use WhiteList. During installation, if a whitelist is provided, this setting is automatically set to 1.

**LISTPATH**<br>
Get Black/White List from external Path (**URL/UNC/Local/GPO**) - download/copy to Winget-AutoUpdate installation location if external list is newer.<br>
**PATH** must end with a Directory, not a File...<br>
...if the external Path is an **URL** and the web host doesn't respond with a date/time header for the file (i.e **GitHub**) then the file is always downloaded!<br>

If the external Path is a Private Azure Container protected by a SAS token (**resourceURI?sasToken**), every special character should be escaped at installation time.<br>
It doesn't work to call Powershell in **CMD** to install **WAU** with the parameter:<br>
`-ListPath https://storagesample.blob.core.windows.net/sample-container?v=2023-11-31&sr=b&sig=39Up9jzHkxhUIhFEjEh9594DIxe6cIRCgOVOICGSP%3A377&sp=rcw`<br>
Instead you must escape **every** special character (notice the `%` escape too) like:<br>
`-ListPath https://storagesample.blob.core.windows.net/sample-container^?v=2023-11-31^&sr=b^&sig=39Up9jzHkxhUIhFEjEh9594DIxe6cIRCgOVOICGSP%%3A377^&sp=rcw`

If `-ListPath` is set to **GPO** the Black/White List can be managed from within the GPO itself under **Application GPO Blacklist**/**Application GPO Whitelist**. Thanks to [Weatherlights](https://github.com/Weatherlights) in [#256 (reply in thread)](https://github.com/Romanitho/Winget-AutoUpdate/discussions/256#discussioncomment-4710599)!

**MODSPATH**<br>
Get Mods from external Path (**URL/UNC/Local/AzureBlob**) - download/copy to `mods` in Winget-AutoUpdate installation location if external mods are newer.<br>
For **URL**: This requires a site directory with **Directory Listing Enabled** and no index page overriding the listing of files (or an index page with href listing of all the **Mods** to be downloaded):
```
<ul>
<li><a  href="Adobe.Acrobat.Reader.32-bit-installed.ps1">Adobe.Acrobat.Reader.32-bit-installed.ps1</a></li>
<li><a  href="Adobe.Acrobat.Reader.64-bit-override.txt">Adobe.Acrobat.Reader.64-bit-override.txt</a></li>
<li><a  href="Notepad++.Notepad++-installed.ps1">Notepad++.Notepad++-installed.ps1</a></li>
<li><a  href="Notepad++.Notepad++-uninstalled.ps1">Notepad++.Notepad++-uninstalled.ps1</a></li>
</ul>
```
Validated on **IIS/Apache**.

>**Nota bene IIS** :
>- The extension **.ps1** must be added as **MIME Types** (text/powershell-script) otherwise it's displayed in the listing but can't be opened
>- Files with special characters in the filename can't be opened by default from an IIS server - config must be administrated: **Enable Allow double escaping** in '**Request Filtering**'

For **AzureBlob**: This requires the parameter **-AzureBlobURL** to be set with an appropriate Azure Blob Storage URL including the SAS token. See **-AzureBlobURL** for more information.

**AZUREBLOBURL**<br>
Used in conjunction with the **-ModsPath** parameter to provide the Azure Storage Blob URL with SAS token. The SAS token must, at a minimum, have 'Read' and 'List' permissions. It is recommended to set the permisions at the container level and rotate the SAS token on a regular basis. Ensure the container reflects the same structure as found under the initial `mods` folder.

**USERCONTEXT**<br>
Default value 0. Set `USERCONTEXT=1` to install WAU with system and **user** context executions.<br>
Applications installed in system context will be ignored under user context.

**BYPASSLISTFORUSERS**<br>
Default value 0. Set `BYPASSLISTFORUSERS=1` to bypass Black/White list when run in user context.

**DESKTOPSHORTCUT**<br>
Set `DESKTOPSHORTCUT=1` to create a shortcut for user interaction on the Desktop to run task `Winget-AutoUpdate`

**STARTMENUSHORTCUT**<br>
Set `STARTMENUSHORTCUT=1` to create shortcuts for user interaction in the Start Menu to run task `Winget-AutoUpdate` and open Logs.

**NOTIFICATIONLEVEL**<br>
Specify the Notification level: Full (Default, displays all notification), SuccessOnly (Only displays notification for success) or None (Does not show any popup).

**UPDATESATLOGON**<br>
Default value 1. Set `UPDATESATLOGON=0` to disable WAU from running at user logon.

**UPDATESINTERVAL**<br>
Default value Never. Specify the update frequency: Daily, BiDaily, Weekly, BiWeekly, Monthly or Never.

**UPDATESATTIME**<br>
Default value 6AM. Specify the time of the update interval execution time.

**DONOTRUNONMETERED**<br>
Default value 1. Set `DONOTRUNONMETERED=0` to force WAU to run on metered connections. May add cellular data costs on shared connexion from smartphone for example.

**MAXLOGFILES**<br>
Specify number of allowed log files.<br>
Default is 3 out of 0-99:<br>
Setting MaxLogFiles to 0 don't delete any old archived log files.<br>
Setting it to 1 keeps the original one and just let it grow.

**MAXLOGSIZE**<br>
Specify the size of the log file in bytes before rotating.<br>
Default is 1048576 = 1 MB (ca. 7500 lines)

**INSTALLDIR**<br>
Specify Winget-AutoUpdate installation location. Default: `C:\Program Files\Winget-AutoUpdate` (Recommended to leave default).



## Custom script (Mods for WAU)
**Mods for WAU** allows you to craft a script to do whatever you like via `_WAU-mods.ps1` in the **mods** folder.<br>
This script executes **if the network is active/any version of Winget is installed/WAU is running as SYSTEM**.<br>
If **ExitCode** is **1** from `_WAU-mods.ps1` then **Re-run WAU**.
## Custom scripts (Mods feature for Apps)
The Mods feature allows you to run additional scripts when upgrading or installing an app.
Just put the scripts in question with the **AppID** followed by the `-preinstall`, `-upgrade`, `-install`, `-installed` or `-notinstalled` suffix in the **mods** folder.

>- Runs before upgrade/install: `AppID-preinstall.ps1`
>- Runs during upgrade/install (before install check): `AppID-upgrade.ps1`/`AppID-install.ps1`
>- Runs after upgrade/install has been confirmed: `AppID-installed.ps1`
>- Runs after a failed upgrade/install: `AppID-notinstalled.ps1`
>- Runs after a failed upgrade/install: `_WAU-notinstalled.ps1` (any individual `AppID-notinstalled.ps1` overrides this global one)

The **-install** mod will be used for upgrades too if **-upgrade** doesn't exist (**WAU** first tries `& $Winget upgrade --id` and if the app isn't detected after that `& $Winget install --id` is tried).<br>
`AppID-install.ps1` is recommended because it's used in **both** scenarios.

> Example:<br>
If you want to run a script that removes the shortcut from **%PUBLIC%\Desktop** (we don't want to fill the desktop with shortcuts our users can't delete) just after installing **Acrobat Reader DC** (32-bit), prepare a powershell script that removes the Public Desktop shortcut **Acrobat Reader DC.lnk** and name your script like this: `Adobe.Acrobat.Reader.32-bit-installed.ps1` and put it in the **mods** folder.

You can find more information on [Winget-Install Repo](https://github.com/Romanitho/Winget-Install#custom-mods), as it's a related feature.<br>
Read more in the `README.md` under the directory **mods**.

Share your mods with the community:<br>
<https://github.com/Romanitho/Winget-AutoUpdate/discussions/categories/mods>

### Winget native parameters
Another finess is the **AppID** followed by the `-override` suffix as a **text file** (.**txt**) that you can place under the **mods** folder.
> Example:<br>
**Canneverbe.CDBurnerXP-override.txt** with the content `ADDLOCAL=All REMOVE=Desktop_Shortcut /qn`

This will use the **content** of the text file as a native **winget --override** parameter when upgrading (as proposed by [JonNesovic](https://github.com/JonNesovic) in [Mod for --override argument #244](https://github.com/Romanitho/Winget-AutoUpdate/discussions/244#discussion-4637666)).

## GPO Management
In an enterprise environment it's crucial that different groups can have different settings in applications etc. or to implement other mandatory settings, i.e for security/management reasons.<br>
**WAU** doesn't have any setting that can be changed except for when installing (or editing the registry/the task `Winget-AutoUpdate` as **Admin**).<br>
With the use of **ADML/ADMX** files you can manage every **WAU** setting from within **GPO**.<br>
They will be detected/evaluated on a daily basis.<br>
The **GPO ADMX/ADML** validated with: [Windows 10 - Validate ADMX for Ingestion](https://web.archive.org/web/20231108145017/https://developer.vmware.com/samples/7115/windows-10---validate-admx-for-ingestion)<br>
Read more in the `README.md` under the directory **Policies**.

![image](https://user-images.githubusercontent.com/102996177/213920242-7ff8e2b4-d926-4407-b860-1e5922e29c3e.png)

## Known issues
* As reported by [soredake](https://github.com/soredake), Powershell from MsStore is not supported with WAU in system context. See <https://github.com/Romanitho/Winget-AutoUpdate/issues/113>

## Optimization
Feel free to give us any suggestions or optimizations in code and support us by adding a star :)

---
<div align="center">

#### WAU - GitHub

[![GitHub release (release name instead of tag name)](https://img.shields.io/github/v/release/Romanitho/Winget-AutoUpdate?display_name=release&include_prereleases&label=Latest%20Release&style=flat-square)](https://github.com/Romanitho/Winget-AutoUpdate/releases/)

</div>
