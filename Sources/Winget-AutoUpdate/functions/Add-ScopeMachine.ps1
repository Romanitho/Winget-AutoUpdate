#Function to configure the preferred scope option as Machine
function Add-ScopeMachine {

    #Get Settings path for system or current user
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $SettingsPath = "$env:windir\System32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings\defaultState\settings.json"
    }
    else {
        $SettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
    }

    $ConfigFile = @{}

    #Check if setting file exist, if not create it
    if (Test-Path $SettingsPath) {
        try {
            # Read the entire file as raw content to preserve structure
            $jsonContent = Get-Content -Path $SettingsPath -Raw -Encoding UTF8
            $ConfigFile = $jsonContent | ConvertFrom-Json
        }
        catch {
            # If JSON parsing fails, create empty config
            Write-Warning "Failed to parse existing settings.json: $($_.Exception.Message)"
            $ConfigFile = New-Object PSObject
        }
    }
    else {
        New-Item -Path $SettingsPath -Force | Out-Null
        $ConfigFile = New-Object PSObject
    }

    # Ensure installBehavior exists
    if (-not $ConfigFile.installBehavior) {
        Add-Member -InputObject $ConfigFile -MemberType NoteProperty -Name "installBehavior" -Value (New-Object PSObject) -Force
    }

    # Ensure preferences exists within installBehavior
    if (-not $ConfigFile.installBehavior.preferences) {
        Add-Member -InputObject $ConfigFile.installBehavior -MemberType NoteProperty -Name "preferences" -Value (New-Object PSObject) -Force
    }

    # Add or update scope preference
    if ($ConfigFile.installBehavior.preferences.scope) {
        $ConfigFile.installBehavior.preferences.scope = "Machine"
    }
    else {
        Add-Member -InputObject $ConfigFile.installBehavior.preferences -MemberType NoteProperty -Name "scope" -Value "Machine" -Force
    }

    $ConfigFile | ConvertTo-Json -Depth 100 | Out-File $SettingsPath -Encoding utf8 -Force
}