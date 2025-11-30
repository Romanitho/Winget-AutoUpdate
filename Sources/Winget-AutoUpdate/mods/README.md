### Mods for WAU (if Network is active/any Winget is installed/running as SYSTEM):
Custom script should be placed here.  
A script **Template** `_WAU-mods-template.ps1` is included to get you started.  
Rename it to `_WAU-mods.ps1` if you want to activate/run it via `Winget-Upgrade.ps1`.

...likewise `_WAU-mods-postsys.ps1` can be used to do things at the end of the **SYSTEM context WAU** process.<br>
A script **Template** `_WAU-mods-postsys-template.ps1` is included to get you started.

### AppID Pre/During/Post install/uninstall:
Custom scripts should be placed here.  
A script **Template** and **Mods Functions** are included as an **example** to get you started...  

Scripts that are considered:  
**AppID**`-preinstall.ps1`, `-upgrade.ps1`, `-install.ps1`, `-installed.ps1` or `-notinstalled.ps1`.  
(`-preuninstall.ps1`, `-uninstall.ps1` or `-uninstalled.ps1` - if used together with [Winget-Install](https://github.com/Romanitho/Winget-Install)).  

>- Runs before upgrade/install: `AppID-preinstall.ps1`  
>- Runs during upgrade/install (before install check): `AppID-upgrade.ps1`/`AppID-install.ps1`  
>- Runs after upgrade/install has been confirmed: `AppID-installed.ps1`  
>- Runs after a failed upgrade/install: `AppID-notinstalled.ps1`  
>- Runs after a failed upgrade/install: `_WAU-notinstalled.ps1` (any individual `AppID-notinstalled.ps1` overrides this global one)

The **-install** mod will be used for upgrades too if **-upgrade** doesn't exist (**WAU** first tries `& $Winget upgrade --id` and if the app isn't detected after that `& $Winget install --id` is tried).  

`AppID-install.ps1` is recommended because it's used in **both** scenarios.

If **AppID**`-preinstall.ps1`/`-preuninstall.ps1` returns `$false`, the install/update/uninstall for that **AppID** is skipped (checking if an App is running, etc...).

A script **Template** for an all-purpose mod (`_WAU-notinstalled-template.ps1`) is included in which actions can be taken if an upgrade/install fails for any **AppID** (any individual `AppID-notinstalled.ps1` overrides this global one)
Name it `_WAU-notinstalled.ps1` for activation

### Winget native parameters:
You can customize winget behavior per-app using **text files** (**.txt**) with specific suffixes:

#### 1. **AppID-override.txt** (Full installer control)
Replaces ALL default installer arguments. Does NOT use `-h` (silent mode).
> Example:  
>  **Adobe.Acrobat.Reader.64-bit-override.txt** with the content:
>  ```
>  "-sfx_nu /sAll /rs /msi EULA_ACCEPT=YES DISABLEDESKTOPSHORTCUT=1"
>  ```

#### 2. **AppID-custom.txt** (Add to installer arguments)
Adds extra arguments to the default installer arguments. Uses `-h` (silent mode).
> Example:  
>  **ShareX.ShareX-custom.txt** with the content:
>  ```
>  /MERGETASKS=!CreateDesktopIcon
>  ```

#### 3. **AppID-arguments.txt** (Winget-level parameters) ⭐ NEW
Passes additional **winget parameters** (not installer arguments). Uses `-h` (silent mode).
> Example:  
>  **Mozilla.Firefox-arguments.txt** with the content:
>  ```
>  --locale pl

> Example:  
>  **Cloudflare.Warp-arguments.txt** with the content:
>  ```
>  --skip-dependencies
>  ```

> Example:  
>  **Microsoft.VisualStudio.2022.Community-arguments.txt** with multiple arguments:
>  ```
>  --locale en-US --architecture x64 --skip-dependencies
>  ```

**Common use cases for `-arguments.txt`:**
- `--locale <locale>` - Set application language (e.g., `pl-PL`, `en-US`, `de-DE`)
- `--skip-dependencies` - Skip dependency installations
- `--architecture <arch>` - Force specific architecture (`x86`, `x64`, `arm64`)
- `--version <version>` - Pin to specific version
- `--ignore-security-hash` - Bypass hash verification
- `--ignore-local-archive-malware-scan` - Skip malware scanning

💡 **Locale Tip:** For applications with locale-specific package IDs (e.g., `Mozilla.Firefox.sv-SE`, `Mozilla.Firefox.de`), use the locale-specific package ID in your `included_apps.txt` instead of the base ID. This prevents WAU from reverting the application language to English during upgrades.

If you must use the base package ID (e.g., `Mozilla.Firefox`), create a `{AppID}-arguments.txt` with `--locale` parameter to force the language during every upgrade.

⚠️ **Important:** When combining `--locale` and `--version`, the specific version must have an installer available for that locale in the winget manifest. Not all versions support all locales.

**Priority order:** `Override` > `Custom` > `Arguments (file)` > `Arguments (command-line)` > `Default`
- If `-override.txt` exists, both `-custom.txt` and `-arguments.txt` are ignored
- If `-custom.txt` exists, `-arguments.txt` is ignored
- If `-arguments.txt` exists, command-line arguments are ignored
- `-arguments.txt` is only used if neither override nor custom exists

**Command-line usage:** You can also pass arguments when calling `Winget-Install.ps1`:
```powershell
.\winget-install.ps1 -AppIDs "Mozilla.Firefox --locale sv-SE"
.\winget-install.ps1 -AppIDs "7zip.7zip --version 23.01 --architecture x64"
```
Note: File-based `-arguments.txt` has priority over command-line arguments.

**Template:** See `_AppID-arguments-template.txt` for more examples and documentation.
