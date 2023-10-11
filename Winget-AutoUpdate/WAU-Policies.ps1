<#
.SYNOPSIS
Handle GPO/Polices

.DESCRIPTION
Daily update settings from policies
#>

#Import functions
. "$PSScriptRoot\functions\Get-WAUConfig.ps1"
. "$PSScriptRoot\functions\Add-Shortcut.ps1"

#Get WAU settings
$WAUConfig = Get-WAUConfig

#Check if GPO got applied from Get-WAUConfig
if ($WAUConfig.WAU_RunGPOManagement -eq 1) {

    #Update 'Winget-AutoUpdate' scheduled task settings
    $taskTriggers = @()
    if ($WAUConfig.WAU_UpdatesAtLogon -eq 1) {
        $tasktriggers += New-ScheduledTaskTrigger -AtLogOn
    }
    if ($WAUConfig.WAU_UpdatesInterval -eq "Daily") {
        $tasktriggers += New-ScheduledTaskTrigger -Daily -At $UpdatesAtTime
    }
    elseif ($WAUConfig.WAU_UpdatesInterval -eq "BiDaily") {
        $tasktriggers += New-ScheduledTaskTrigger -Daily -At $UpdatesAtTime -DaysInterval 2
    }
    elseif ($WAUConfig.WAU_UpdatesInterval -eq "Weekly") {
        $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $UpdatesAtTime -DaysOfWeek 2
    }
    elseif ($WAUConfig.WAU_UpdatesInterval -eq "BiWeekly") {
        $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 2
    }
    elseif ($WAUConfig.WAU_UpdatesInterval -eq "Monthly") {
        $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 4
    }
    if ($taskTriggers) {
        Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue | Set-ScheduledTask -Trigger $taskTriggers
    }

    #Update Desktop shortcut
    $DesktopShortcut = "${env:Public}\Desktop\WAU - Check for updated Apps.lnk"
    if (($WAUConfig.WAU_DesktopShortcut -eq 1) -and !(Test-Path $DesktopShortcut)) {
        Add-Shortcut "wscript.exe" $DesktopShortcut "`"$($WAUConfig.InstallLocation)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WAUConfig.InstallLocation)\user-run.ps1`"`"" "${env:SystemRoot}\System32\shell32.dll,-16739" "Manual start of Winget-AutoUpdate (WAU)..."
    }
    elseif ($WAUConfig.WAU_DesktopShortcut -ne 1) {
        Remove-Item -Path $DesktopShortcut -Force | Out-Null
    }

    #Update Start Menu shortcuts
    $StartMenuShortcut = "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)"
    if (($WAUConfig.WAU_StartMenuShortcut -eq 1) -and !(Test-Path $StartMenuShortcut)) {
        New-Item -ItemType Directory -Force -Path $StartMenuShortcut | Out-Null
        Add-Shortcut "wscript.exe" "$StartMenuShortcut\WAU - Check for updated Apps.lnk" "`"$($WAUConfig.InstallLocation)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WAUConfig.InstallLocation)\user-run.ps1`"`"" "${env:SystemRoot}\System32\shell32.dll,-16739" "Manual start of Winget-AutoUpdate (WAU)..."
        Add-Shortcut "wscript.exe" "$StartMenuShortcut\WAU - Open logs.lnk" "`"$($WAUConfig.InstallLocation)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WAUConfig.InstallLocation)\user-run.ps1`" -Logs`"" "${env:SystemRoot}\System32\shell32.dll,-16763" "Open existing WAU logs..."
        Add-Shortcut "wscript.exe" "$StartMenuShortcut\WAU - Web Help.lnk" "`"$($WAUConfig.InstallLocation)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WAUConfig.InstallLocation)\user-run.ps1`" -Help`"" "${env:SystemRoot}\System32\shell32.dll,-24" "Help for WAU..."
    }
    elseif ($WAUConfig.WAU_StartMenuShortcut -ne 1) {
        Remove-Item -Path $StartMenuShortcut -Recurse -Force | Out-Null
    }

    #Log latest applied config
    $GPOLogFile = "$($WAUConfig.InstallLocation)\logs\LatestAppliedSettings.txt"
    Set-Content -Path $GPOLogFile -Value "### POLICY CYCLE - $(Get-Date) ###"
    $WAUConfig.PSObject.Properties | Where-Object { $_.Name -like "WAU_*" } | Select-Object Name, Value | Out-File -FilePath $GPOLogFile -Append

    #Reset WAU_RunGPOManagement if not GPO managed anymore (This is used to run this job one last time and reset initial settings)
    if ($($WAUPolicies.WAU_ActivateGPOManagement -eq 1)) {
        Add-Content -Path $GPOLogFile -Value "GPO Management Enabled."
    }
    else {
        New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" -Name WAU_RunGPOManagement -Value 0 -Force | Out-Null
        Add-Content -Path $GPOLogFile -Value "GPO Management Disabled. Policies removed."
    }
}

Exit 0