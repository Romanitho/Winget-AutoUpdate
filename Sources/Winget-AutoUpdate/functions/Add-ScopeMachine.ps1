#Function to configure the prefered scope option as Machine
function Add-ScopeMachine {

    #Get Settings path for system or current user
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $SettingsPath = "$Env:windir\System32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings\defaultState\settings.json"
    }
    else {
        $SettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
    }

    $ConfigFile = @{}

    #Check if setting file exist, if not create it
    if (Test-Path $SettingsPath) {
        $ConfigFile = Get-Content -Path $SettingsPath | Where-Object { $_ -notmatch '//' } | ConvertFrom-Json
    }
    else {
        New-Item -Path $SettingsPath -Force | Out-Null
    }

    if ($ConfigFile.installBehavior.preferences) {
        Add-Member -InputObject $ConfigFile.installBehavior.preferences -MemberType NoteProperty -Name "scope" -Value "Machine" -Force
    }
    else {
        $Scope = New-Object PSObject -Property $(@{scope = "Machine" })
        $Preference = New-Object PSObject -Property $(@{preferences = $Scope })
        Add-Member -InputObject $ConfigFile -MemberType NoteProperty -Name "installBehavior" -Value $Preference -Force
    }

    $ConfigFile | ConvertTo-Json -Depth 100 | Out-File $SettingsPath -Encoding utf8 -Force
}