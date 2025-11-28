<#
.SYNOPSIS
    Configures WinGet to prefer machine-scope installations.

.DESCRIPTION
    Updates the WinGet settings file to set the installation scope
    preference to "Machine". This ensures applications are installed
    for all users when running in system context.

.EXAMPLE
    Add-ScopeMachine

.NOTES
    Settings file location varies by context:
    - System: %WINDIR%\System32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings
    - User: %LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState
#>
function Add-ScopeMachine {

    # Determine settings path based on execution context
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $SettingsPath = "$Env:windir\System32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings\defaultState\settings.json"
    }
    else {
        $SettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
    }

    $ConfigFile = @{}

    # Load existing settings or create new file
    if (Test-Path $SettingsPath) {
        # Parse JSON, excluding comment lines
        $ConfigFile = Get-Content -Path $SettingsPath | Where-Object { $_ -notmatch '//' } | ConvertFrom-Json
    }
    else {
        New-Item -Path $SettingsPath -Force | Out-Null
    }

    # Add or update the installBehavior.preferences.scope setting
    if ($ConfigFile.installBehavior.preferences) {
        Add-Member -InputObject $ConfigFile.installBehavior.preferences -MemberType NoteProperty -Name "scope" -Value "Machine" -Force
    }
    else {
        # Create the nested structure if it doesn't exist
        $Scope = New-Object PSObject -Property $(@{scope = "Machine" })
        $Preference = New-Object PSObject -Property $(@{preferences = $Scope })
        Add-Member -InputObject $ConfigFile -MemberType NoteProperty -Name "installBehavior" -Value $Preference -Force
    }

    # Save the updated settings
    $ConfigFile | ConvertTo-Json -Depth 100 | Out-File $SettingsPath -Encoding utf8 -Force
}
