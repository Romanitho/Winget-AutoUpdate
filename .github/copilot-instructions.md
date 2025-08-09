# Copilot Instructions for Winget-AutoUpdate

## Project Overview
- **Winget-AutoUpdate (WAU)** automates daily updates of Windows applications using the `winget` tool, supporting both system and user contexts.
- The project is PowerShell-centric, with core scripts in `Sources/Winget-AutoUpdate/` and modular functions in `functions/`.
- GPO/Intune management is supported via ADMX/ADML templates in `Sources/Policies/ADMX/`.
- Customization is enabled through "Mods" scripts in `Sources/Winget-AutoUpdate/mods/`.

## Key Components
- **Main scripts:**
  - `Winget-Upgrade.ps1`: Main update logic, loads all functions from `functions/`.
  - `Winget-Install.ps1`: Used for deployment scenarios (Intune/SCCM).
  - `WAU-Notify.ps1`, `WAU-Policies.ps1`: Notification and policy handling.
- **Functions:** Each PowerShell file in `functions/` implements a single responsibility (e.g., `Get-ExcludedApps.ps1`, `Update-App.ps1`).
- **Mods:**
  - Place custom scripts in `mods/` to hook into app install/upgrade events (see `mods/README.md`).
  - Supported hooks: `-preinstall`, `-upgrade`, `-install`, `-installed`, `-notinstalled`.
  - Global mods: `_WAU-mods.ps1`, `_WAU-mods-postsys.ps1`, `_WAU-notinstalled.ps1`.
- **GPO/Intune:**
  - ADMX/ADML files in `Sources/Policies/ADMX/` allow central management of WAU settings.
  - Since v1.16.5, GPO Black/White lists are auto-detected—no need to set `-ListPath GPO`.

## Developer Workflows
- **No build step**: Scripts are run directly via PowerShell.
- **Testing:**
  - No formal test suite; test by running scripts with various parameters and checking logs in `logs/`.
- **Debugging:**
  - Logs are written to `logs/updates.log` (system context).
  - Use `Write-ToLog` for custom debug output.
- **Deployment:**
  - MSI installer is built using Wix (see `Wix/`).
- Deploy via Intune/SCCM by installing the MSI package (WAU.msi).

## Project Conventions
- **All functions are dot-sourced at runtime from the `functions/` directory.**
- **Mods**: Use the provided templates in `mods/` for custom logic. Scripts are matched by naming convention.
- **GPO/Intune**: Only the `en-US` ADML file is supported.
- **Lists**: `excluded_apps.txt` and `included_apps.txt` are used unless a GPO list is present (GPO always takes precedence).
- **Wildcard support**: App lists support `*` wildcards (e.g., `Mozilla.Firefox*`).

## Integration Points
- **winget**: All app management is via the Windows Package Manager CLI.
- **GPO/Intune**: Settings are read from registry or policy files if present.
- **Wix**: Used for MSI packaging (see `Wix/build.wxs`).

## Examples
- To add a global mod: copy `_WAU-mods-template.ps1` to `_WAU-mods.ps1` and customize.
- To exclude an app: add its ID to `excluded_apps.txt` or configure via GPO.
- To deploy via Intune: use `Winget-Install.ps1` with appropriate parameters.

For more, see `README.md`, `Sources/Policies/README.md`, and `Sources/Winget-AutoUpdate/mods/README.md`.
