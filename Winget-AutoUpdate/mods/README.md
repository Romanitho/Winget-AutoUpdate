Pre/During/Post install/uninstall custom scripts should be placed here.  
A script **Template** and **Mods Functions** are included as **example** to get you started...  

Scripts that are considered:  
**AppID**`-preinstall.ps1`, `-upgrade.ps1`, `-install.ps1`, `-installed.ps1`, `-preuninstall.ps1`, `-uninstall.ps1` or `-uninstalled.ps1`  

The **-install** mod will be used for upgrades too if **-upgrade** doesn't exist (**WAU** first tries `& $Winget upgrade --id` and if the app isn't detected after that `& $Winget install --id` is tried).  
`AppID-install.ps1` is recommended because it's used in **both** scenarios.

**AppID**`-override.txt` (the content) will be used as a native **winget --override** parameter when upgrading
