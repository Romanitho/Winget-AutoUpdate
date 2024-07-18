#Function to make actions after WAU update

function Invoke-PostUpdateActions {

    #log
    Write-ToLog "Running Post Update actions:" "yellow"

    #Update Winget if not up to date
    $null = Update-WinGet

    #Create WAU Regkeys if not present
    $InstallRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
    if (!(test-path $InstallRegPath)) {
        New-Item $InstallRegPath -Force
        New-ItemProperty $InstallRegPath -Name DisplayName -Value "Winget-AutoUpdate (WAU)" -Force
        New-ItemProperty $InstallRegPath -Name DisplayIcon -Value "C:\Windows\System32\shell32.dll,-16739" -Force
        New-ItemProperty $InstallRegPath -Name NoModify -Value 1 -Force
        New-ItemProperty $InstallRegPath -Name NoRepair -Value 1 -Force
        New-ItemProperty $InstallRegPath -Name Publisher -Value "Romanitho" -Force
        New-ItemProperty $InstallRegPath -Name URLInfoAbout -Value "https://github.com/Romanitho/Winget-AutoUpdate" -Force
        New-ItemProperty $InstallRegPath -Name UninstallString -Value "powershell.exe -noprofile -executionpolicy bypass -file `"$WorkingDir\WAU-Uninstall.ps1`"" -Force
        New-ItemProperty $InstallRegPath -Name QuietUninstallString -Value "powershell.exe -noprofile -executionpolicy bypass -file `"$WorkingDir\WAU-Uninstall.ps1`"" -Force
        #log
        Write-ToLog "-> $InstallRegPath created." "green"
    }
    #Migrate configuration if not already done
    $ConfigRegPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
    if (!(test-path $ConfigRegPath)) {
        New-Item -Path $ConfigRegPath -Force
        New-ItemProperty $ConfigRegPath -Name InstallLocation -Value $WorkingDir -Force
        $Keys = Get-Item $InstallRegPath
        foreach ($Key in $Keys.Property) {
            if ($Key -like "WAU_*") {
                Move-ItemProperty $InstallRegPath -Name $Key -Destination $ConfigRegPath
            }
            elseif ($Key -eq "DisplayVersion") {
                Copy-ItemProperty $InstallRegPath -Name "DisplayVersion" -Destination $ConfigRegPath
                Rename-ItemProperty $ConfigRegPath -Name "DisplayVersion" -NewName "ProductVersion"
            }
            elseif ($Key -eq "InstallLocation") {
                Copy-ItemProperty $InstallRegPath -Name $Key -Destination $ConfigRegPath
            }
        }
        #log
        Write-ToLog "-> $ConfigRegPath created. Config migrated." "green"
        #Reload config
        $Script:WAUConfig = Get-WAUConfig
    }
    #Fix Notif where WAU_NotificationLevel is not set
    $regNotif = Get-ItemProperty $ConfigRegPath -Name WAU_NotificationLevel -ErrorAction SilentlyContinue
    if (!$regNotif) {
        New-ItemProperty $ConfigRegPath -Name WAU_NotificationLevel -Value Full -Force

        #log
        Write-ToLog "-> Notification level setting was missing. Fixed with 'Full' option."
    }

    #Set WAU_MaxLogFiles/WAU_MaxLogSize if not set
    $MaxLogFiles = Get-ItemProperty $ConfigRegPath -Name WAU_MaxLogFiles -ErrorAction SilentlyContinue
    if (!$MaxLogFiles) {
        New-ItemProperty $ConfigRegPath -Name WAU_MaxLogFiles -Value 3 -PropertyType DWord -Force | Out-Null
        New-ItemProperty $ConfigRegPath -Name WAU_MaxLogSize -Value 1048576 -PropertyType DWord -Force | Out-Null

        #log
        Write-ToLog "-> MaxLogFiles/MaxLogSize setting was missing. Fixed with 3/1048576 (in bytes, default is 1048576 = 1 MB)."
    }

    #Security check
    Write-ToLog "-> Checking Mods Directory:" "yellow"
    $Protected = Invoke-DirProtect "$($WAUConfig.InstallLocation)\mods"
    if ($Protected -eq $True) {
        Write-ToLog "-> The mods directory is secured!" "green"
    }
    else {
        Write-ToLog "-> Error: The mods directory couldn't be verified as secured!" "red"
    }
    Write-ToLog "-> Checking Functions Directory:" "yellow"
    $Protected = Invoke-DirProtect "$($WAUConfig.InstallLocation)\Functions"
    if ($Protected -eq $True) {
        Write-ToLog "-> The Functions directory is secured!" "green"
    }
    else {
        Write-ToLog "-> Error: The Functions directory couldn't be verified as secured!" "red"
    }

    #Remove old functions / files
    $FileNames = @(
        "$WorkingDir\functions\Start-Init.ps1",
        "$WorkingDir\functions\Get-Policies.ps1",
        "$WorkingDir\functions\Get-WAUCurrentVersion.ps1",
        "$WorkingDir\functions\Get-WAUUpdateStatus.ps1",
        "$WorkingDir\functions\Write-Log.ps1",
        "$WorkingDir\functions\Get-WinGetAvailableVersion.ps1",
        "$WorkingDir\functions\Invoke-ModsProtect.ps1",
        "$WorkingDir\Version.txt"
    )
    foreach ($FileName in $FileNames) {
        if (Test-Path $FileName) {
            Remove-Item $FileName -Force -Confirm:$false

            #log
            Write-ToLog "-> $FileName removed." "green"
        }
    }

    #Activate WAU in user context if previously configured (as "Winget-AutoUpdate-UserContext" at root)
    $UserContextTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -TaskPath '\' -ErrorAction SilentlyContinue
    if ($UserContextTask) {
        #Remove Winget-AutoUpdate-UserContext at root.
        $null = $UserContextTask | Unregister-ScheduledTask -Confirm:$False

        #Set it in registry as activated.
        New-ItemProperty $ConfigRegPath -Name WAU_UserContext -Value 1 -PropertyType DWord -Force | Out-Null
        Write-ToLog "-> Old User Context task deleted and set to 'enabled' in registry."
    }

    #Set GPO scheduled task if not existing
    $GPOTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate-Policies' -ErrorAction SilentlyContinue
    if (!$GPOTask) {
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($WorkingDir)\WAU-Policies.ps1`""
        $tasktrigger = New-ScheduledTaskTrigger -Daily -At 6am
        $taskUserPrincipal = New-ScheduledTaskPrincipal -UserId S-1-5-18 -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00
        # Set up the task, and register it
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings -Trigger $taskTrigger
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-Policies' -TaskPath 'WAU' -InputObject $task -Force | Out-Null
        Write-ToLog "-> Policies task created."
    }


    ### End of post update actions ###

    #Reset WAU_UpdatePostActions Value
    New-ItemProperty -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate" -Name "WAU_PostUpdateActions" -Value 0 -Force | Out-Null

    #Get updated WAU Config
    $Script:WAUConfig = Get-WAUConfig

    #Add 1 to counter file
    try {
        Invoke-RestMethod -Uri "https://github.com/Romanitho/Winget-AutoUpdate/releases/download/v$($WAUConfig.DisplayVersion)/WAU_InstallCounter" | Out-Null
    }
    catch {
        Write-ToLog "-> Not able to report installation." "Yellow"
    }

    #log
    Write-ToLog "Post Update actions finished" "green"

}
