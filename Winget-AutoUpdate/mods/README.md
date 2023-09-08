### Mods for WAU (if Network is active/any Winget is installed/running as SYSTEM):
Custom script should be placed here.  
A script **Template** `_WAU-mods-template.ps1` is included to get you started.  
Rename it to `_WAU-mods.ps1` if you want to activate/run it via `Winget-Upgrade.ps1`.
### Pre/During/Post install/uninstall:
Custom scripts should be placed here.  
A script **Template** and **Mods Functions** are included as an **example** to get you started...  

Scripts that are considered:  
**AppID**`-preinstall.ps1`, `-upgrade.ps1`, `-install.ps1` or `-installed.ps1`.  
(`-preuninstall.ps1`, `-uninstall.ps1` or `-uninstalled.ps1` - if used together with [Winget-Install](https://github.com/Romanitho/Winget-Install)).  

> Runs before upgrade/install: `AppID-preinstall.ps1`  
> Runs during upgrade/install (before install check): `AppID-upgrade.ps1`/`AppID-install.ps1`  
> Runs after upgrade/install has been confirmed: `AppID-installed.ps1`  

The **-install** mod will be used for upgrades too if **-upgrade** doesn't exist (**WAU** first tries `& $Winget upgrade --id` and if the app isn't detected after that `& $Winget install --id` is tried).  

`AppID-install.ps1` is recommended because it's used in **both** scenarios.

### Winget native parameters:
Another finess is the **AppID** followed by the `-override` suffix as a **text file** (**.txt**).
> Example:  
>  **Canneverbe.CDBurnerXP-override.txt** with the content `ADDLOCAL=All REMOVE=Desktop_Shortcut /qn`

This will use the **content** of the text file as a native **winget --override** parameter in **WAU upgrading**.
