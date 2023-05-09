#Function to configure the prefered scope option as Machine
function Add-ScopeMachine ($SettingsPath) {

    if (Test-Path $SettingsPath) {
        $ConfigFile = Get-Content -Path $SettingsPath | Where-Object { $_ -notmatch '//' } | ConvertFrom-Json
    }
    if (!$ConfigFile) {
        $ConfigFile = @{}
    }
    if ($ConfigFile.installBehavior.preferences.scope) {
        $ConfigFile.installBehavior.preferences.scope = "Machine"
    }
    else {
        $Scope = New-Object PSObject -Property $(@{scope = "Machine" })
        $Preference = New-Object PSObject -Property $(@{preferences = $Scope })
        Add-Member -InputObject $ConfigFile -MemberType NoteProperty -Name 'installBehavior' -Value $Preference -Force
    }
    $ConfigFile | ConvertTo-Json | Out-File $SettingsPath -Encoding utf8 -Force

}
