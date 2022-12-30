#Function to get Domain/Local Policies (GPO)

Function Get-Policies {
    #Get WAU Policies and set the Configurations Registry Accordingly
    $WAUPolicies = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -ErrorAction SilentlyContinue
    if ($WAUPolicies) {
        if ($($WAUPolicies.WAU_ActivateGPOManagement -eq 1)) {
            $ChangedSettings = 0
            Write-Log "Activated WAU GPO Management detected, comparing..."
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
            if ($null -ne $($WAUPolicies.WAU_BypassListForUsers) -and ($($WAUPolicies.WAU_BypassListForUsers) -ne $($WAUConfig.WAU_BypassListForUsers))) {
                New-ItemProperty $regPath -Name WAU_BypassListForUsers -Value $($WAUPolicies.WAU_BypassListForUsers) -PropertyType DWord -Force | Out-Null
                $ChangedSettings++
            }
            elseif ($null -eq $($WAUPolicies.WAU_BypassListForUsers) -and ($($WAUConfig.WAU_BypassListForUsers) -or $($WAUConfig.WAU_BypassListForUsers) -eq 0)) {
                Remove-ItemProperty $regPath -Name WAU_BypassListForUsers -Force -ErrorAction SilentlyContinue | Out-Null
                $ChangedSettings++
            }
    
            if ($null -ne $($WAUPolicies.WAU_DisableAutoUpdate) -and ($($WAUPolicies.WAU_DisableAutoUpdate) -ne $($WAUConfig.WAU_DisableAutoUpdate))) {
                New-ItemProperty $regPath -Name WAU_DisableAutoUpdate -Value $($WAUPolicies.WAU_DisableAutoUpdate) -PropertyType DWord -Force | Out-Null
                $ChangedSettings++
            }
            elseif ($null -eq $($WAUPolicies.WAU_DisableAutoUpdate) -and ($($WAUConfig.WAU_DisableAutoUpdate) -or $($WAUConfig.WAU_DisableAutoUpdate) -eq 0)) {
                Remove-ItemProperty $regPath -Name WAU_DisableAutoUpdate -Force -ErrorAction SilentlyContinue | Out-Null
                $ChangedSettings++
            }
    
            if ($null -ne $($WAUPolicies.WAU_DoNotRunOnMetered) -and ($($WAUPolicies.WAU_DoNotRunOnMetered) -ne $($WAUConfig.WAU_DoNotRunOnMetered))) {
                New-ItemProperty $regPath -Name WAU_DoNotRunOnMetered -Value $($WAUPolicies.WAU_DoNotRunOnMetered) -PropertyType DWord -Force | Out-Null
                $ChangedSettings++
            }
            elseif ($null -eq $($WAUPolicies.WAU_DoNotRunOnMetered) -and !$($WAUConfig.WAU_DoNotRunOnMetered)) {
                New-ItemProperty $regPath -Name WAU_DoNotRunOnMetered -Value 1 -PropertyType DWord -Force | Out-Null
                $ChangedSettings++
            }
    
            if ($null -ne $($WAUPolicies.WAU_UpdatePrerelease) -and ($($WAUPolicies.WAU_UpdatePrerelease) -ne $($WAUConfig.WAU_UpdatePrerelease))) {
                New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value $($WAUPolicies.WAU_UpdatePrerelease) -PropertyType DWord -Force | Out-Null
                $ChangedSettings++
            }
            elseif ($null -eq $($WAUPolicies.WAU_UpdatePrerelease) -and $($WAUConfig.WAU_UpdatePrerelease)) {
                New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 0 -PropertyType DWord -Force | Out-Null
                $ChangedSettings++
            }
    
            if ($null -ne $($WAUPolicies.WAU_UseWhiteList) -and ($($WAUPolicies.WAU_UseWhiteList) -ne $($WAUConfig.WAU_UseWhiteList))) {
                New-ItemProperty $regPath -Name WAU_UseWhiteList -Value $($WAUPolicies.WAU_UseWhiteList) -PropertyType DWord -Force | Out-Null
                $ChangedSettings++
            }
            elseif ($null -eq $($WAUPolicies.WAU_UseWhiteList) -and ($($WAUConfig.WAU_UseWhiteList) -or $($WAUConfig.WAU_UseWhiteList) -eq 0)) {
                Remove-ItemProperty $regPath -Name WAU_UseWhiteList -Force -ErrorAction SilentlyContinue | Out-Null
                $ChangedSettings++
            }
    
            if ($null -ne $($WAUPolicies.WAU_ListPath) -and ($($WAUPolicies.WAU_ListPath.TrimEnd(" ", "\", "/")) -ne $($WAUConfig.WAU_ListPath.TrimEnd(" ", "\", "/")))) {
                New-ItemProperty $regPath -Name WAU_ListPath -Value $($WAUPolicies.WAU_ListPath.TrimEnd(" ", "\", "/")) -Force | Out-Null
                $ChangedSettings++
            }
            elseif ($null -eq $($WAUPolicies.WAU_ListPath) -and $($WAUConfig.WAU_ListPath)) {
                Remove-ItemProperty $regPath -Name WAU_ListPath -Force -ErrorAction SilentlyContinue | Out-Null
                $ChangedSettings++
            }
    
            if ($null -ne $($WAUPolicies.WAU_ModsPath) -and ($($WAUPolicies.WAU_ModsPath.TrimEnd(" ", "\", "/")) -ne $($WAUConfig.WAU_ModsPath.TrimEnd(" ", "\", "/")))) {
                New-ItemProperty $regPath -Name WAU_ModsPath -Value $($WAUPolicies.WAU_ModsPath.TrimEnd(" ", "\", "/")) -Force | Out-Null
                $ChangedSettings++
            }
            elseif ($null -eq $($WAUPolicies.WAU_ModsPath) -and $($WAUConfig.WAU_ModsPath)) {
                Remove-ItemProperty $regPath -Name WAU_ModsPath -Force -ErrorAction SilentlyContinue | Out-Null
                $ChangedSettings++
            }

            if ($null -ne $($WAUPolicies.WAU_NotificationLevel) -and ($($WAUPolicies.WAU_NotificationLevel) -ne $($WAUConfig.WAU_NotificationLevel))) {
                New-ItemProperty $regPath -Name WAU_NotificationLevel -Value $($WAUPolicies.WAU_NotificationLevel) -Force | Out-Null
                $ChangedSettings++
            }
            elseif ($null -eq $($WAUPolicies.WAU_NotificationLevel) -and $($WAUConfig.WAU_NotificationLevel) -ne "Full") {
                New-ItemProperty $regPath -Name WAU_NotificationLevel -Value "Full" -Force | Out-Null
                $ChangedSettings++
            }

            if ($null -ne $($WAUPolicies.WAU_UpdatesAtTime) -and ($($WAUPolicies.WAU_UpdatesAtTime) -ne $($WAUConfig.WAU_UpdatesAtTime))) {
                New-ItemProperty $regPath -Name WAU_UpdatesAtTime -Value $($WAUPolicies.WAU_UpdatesAtTime) -Force | Out-Null
                $Script:WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
                $ChangedSettings++
            }
            elseif ($null -eq $($WAUPolicies.WAU_UpdatesAtTime) -and $($WAUConfig.WAU_UpdatesAtTime) -ne "06:00:00") {
                New-ItemProperty $regPath -Name WAU_UpdatesAtTime -Value "06:00:00" -Force | Out-Null
                $Script:WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
                $ChangedSettings++
            }

            if ($null -ne $($WAUPolicies.WAU_UpdatesInterval) -and (($($WAUPolicies.WAU_UpdatesInterval) -ne $($WAUConfig.WAU_UpdatesInterval)))) {
                New-ItemProperty $regPath -Name WAU_UpdatesInterval -Value $($WAUPolicies.WAU_UpdatesInterval) -Force | Out-Null
                $service = New-Object -ComObject Schedule.Service
                $service.Connect($env:COMPUTERNAME)
                $folder = $service.GetFolder('\')
                $task = $folder.GetTask("Winget-AutoUpdate")
                $definition = $task.Definition
                for($triggerId=1; $triggerId -le $definition.Triggers.Count; $triggerId++){
                    if(($definition.Triggers.Item($triggerId).Type -eq "2") -or ($definition.Triggers.Item($triggerId).Type -eq "3")){
                        $UpdatesAtTime = ($definition.Triggers.Item($triggerId).StartBoundary).Substring(11,8)
                        $definition.Triggers.Remove($triggerId)
                        $triggerId-=1
                    }
                }
                $folder.RegisterTaskDefinition($task.Name, $definition, 4, $null, $null, $null) | Out-Null

                if (!$($WAUConfig.WAU_UpdatesAtTime)) {
                    New-ItemProperty $regPath -Name WAU_UpdatesAtTime -Value $UpdatesAtTime -Force | Out-Null
                    $Script:WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
                }

                if ($($WAUPolicies.WAU_UpdatesInterval) -ne "Never") {
                    #Count Triggers (correctly)
                    $service = New-Object -ComObject Schedule.Service
                    $service.Connect($env:COMPUTERNAME)
                    $folder = $service.GetFolder('\')
                    $task = $folder.GetTask("Winget-AutoUpdate")
                    $definition = $task.Definition
                    $definition.Triggers.Count | Out-Null
                    switch ($($WAUPolicies.WAU_UpdatesInterval)) {
                        "Daily" {$tasktrigger = New-ScheduledTaskTrigger -Daily -At $($WAUConfig.WAU_UpdatesAtTime); break}
                        "BiDaily" {$tasktrigger = New-ScheduledTaskTrigger -Daily -At $($WAUConfig.WAU_UpdatesAtTime) -DaysInterval 2; break}
                        "Weekly" {$tasktrigger = New-ScheduledTaskTrigger -Weekly -At $($WAUConfig.WAU_UpdatesAtTime) -DaysOfWeek 2; break}
                        "BiWeekly" {$tasktrigger = New-ScheduledTaskTrigger -Weekly -At $($WAUConfig.WAU_UpdatesAtTime) -DaysOfWeek 2 -WeeksInterval 2; break}
                        "Monthly" {$tasktrigger = New-ScheduledTaskTrigger -Weekly -At $($WAUConfig.WAU_UpdatesAtTime) -DaysOfWeek 2 -WeeksInterval 4; break}
                    }
                    if ($definition.Triggers.Count -gt 0) {
                        $triggers = @()
                        $triggers += (Get-ScheduledTask "Winget-AutoUpdate").Triggers
                        $triggers += $tasktrigger
                        Set-ScheduledTask -TaskName "Winget-AutoUpdate" -Trigger $triggers
                    }
                    else {
                        Set-ScheduledTask -TaskName "Winget-AutoUpdate" -Trigger $tasktrigger
                    }
                }
                $ChangedSettings++
            }
            elseif ($null -eq $($WAUPolicies.WAU_UpdatesInterval) -and $($WAUConfig.WAU_UpdatesInterval) -ne "Daily") {
                New-ItemProperty $regPath -Name WAU_UpdatesInterval -Value "Daily" -Force | Out-Null
                $service = New-Object -ComObject Schedule.Service
                $service.Connect($env:COMPUTERNAME)
                $folder = $service.GetFolder('\')
                $task = $folder.GetTask("Winget-AutoUpdate")
                $definition = $task.Definition
                for($triggerId=1; $triggerId -le $definition.Triggers.Count; $triggerId++){
                    if(($definition.Triggers.Item($triggerId).Type -eq "2") -or ($definition.Triggers.Item($triggerId).Type -eq "3")){
                        $UpdatesAtTime = ($definition.Triggers.Item($triggerId).StartBoundary).Substring(11,8)
                        $definition.Triggers.Remove($triggerId)
                        $triggerId-=1
                    }
                }
                $folder.RegisterTaskDefinition($task.Name, $definition, 4, $null, $null, $null) | Out-Null

                if (!$($WAUConfig.WAU_UpdatesAtTime)) {
                    New-ItemProperty $regPath -Name WAU_UpdatesAtTime -Value $UpdatesAtTime -Force | Out-Null
                    $Script:WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
                }

                $tasktrigger = New-ScheduledTaskTrigger -Daily -At $($WAUConfig.WAU_UpdatesAtTime)

                #Count Triggers (correctly)
                $service = New-Object -ComObject Schedule.Service
                $service.Connect($env:COMPUTERNAME)
                $folder = $service.GetFolder('\')
                $task = $folder.GetTask("Winget-AutoUpdate")
                $definition = $task.Definition
                $definition.Triggers.Count | Out-Null
                if ($definition.Triggers.Count -gt 0) {
                    $triggers = @()
                    $triggers += (Get-ScheduledTask "Winget-AutoUpdate").Triggers
                    $triggers += $tasktrigger
                    Set-ScheduledTask -TaskName "Winget-AutoUpdate" -Trigger $triggers
                }
                else {
                    Set-ScheduledTask -TaskName "Winget-AutoUpdate" -Trigger $tasktrigger
                }
                $ChangedSettings++
            }

            if ($null -ne $($WAUPolicies.WAU_UpdatesAtLogon) -and ($($WAUPolicies.WAU_UpdatesAtLogon) -ne $($WAUConfig.WAU_UpdatesAtLogon))) {
                if ($WAUPolicies.WAU_UpdatesAtLogon -eq 1) {
                    New-ItemProperty $regPath -Name WAU_UpdatesAtLogon -Value $($WAUPolicies.WAU_UpdatesAtLogon) -PropertyType DWord -Force | Out-Null
                    $triggers = @()
                    $triggers += (Get-ScheduledTask "Winget-AutoUpdate").Triggers
                    #Count Triggers (correctly)
                    $service = New-Object -ComObject Schedule.Service
                    $service.Connect($env:COMPUTERNAME)
                    $folder = $service.GetFolder('\')
                    $task = $folder.GetTask("Winget-AutoUpdate")
                    $definition = $task.Definition
                    $definition.Triggers.Count | Out-Null
                    if ($definition.Triggers.Count -gt 0) {
                        $triggers += New-ScheduledTaskTrigger -AtLogon
                        Set-ScheduledTask -TaskName "Winget-AutoUpdate" -Trigger $triggers
                    }
                    else {
                        $tasktrigger = New-ScheduledTaskTrigger -AtLogon
                        Set-ScheduledTask -TaskName "Winget-AutoUpdate" -Trigger $tasktrigger
                    }
                }
                else {
                    Remove-ItemProperty $regPath -Name WAU_UpdatesAtLogon -Force -ErrorAction SilentlyContinue | Out-Null
                    $service = New-Object -ComObject Schedule.Service
                    $service.Connect($env:COMPUTERNAME)
                    $folder = $service.GetFolder('\')
                    $task = $folder.GetTask("Winget-AutoUpdate")
                    $definition = $task.Definition
                    $definition.Triggers.Count | Out-Null
                    for($triggerId=1; $triggerId -le $definition.Triggers.Count; $triggerId++){
                        if($definition.Triggers.Item($triggerId).Type -eq "9"){
                            $definition.Triggers.Remove($triggerId)
                            $triggerId-=1
                        }
                    }
                    $folder.RegisterTaskDefinition($task.Name, $definition, 4, $null, $null, $null) | Out-Null
                }
                $ChangedSettings++
            }
            elseif ($null -eq $($WAUPolicies.WAU_UpdatesAtLogon) -and ($($WAUConfig.WAU_UpdatesAtLogon) -or $($WAUConfig.WAU_UpdatesAtLogon) -eq 0)) {
                Remove-ItemProperty $regPath -Name WAU_UpdatesAtLogon -Force -ErrorAction SilentlyContinue | Out-Null
                $service = New-Object -ComObject Schedule.Service
                $service.Connect($env:COMPUTERNAME)
                $folder = $service.GetFolder('\')
                $task = $folder.GetTask("Winget-AutoUpdate")
                $definition = $task.Definition
                for($triggerId=1; $triggerId -le $definition.Triggers.Count; $triggerId++){
                    if($definition.Triggers.Item($triggerId).Type -eq "9"){
                        $definition.Triggers.Remove($triggerId)
                        $triggerId-=1
                    }
                }
                $folder.RegisterTaskDefinition($task.Name, $definition, 4, $null, $null, $null) | Out-Null
                $ChangedSettings++
            }

            if ($null -ne $($WAUPolicies.WAU_UserContext) -and ($($WAUPolicies.WAU_UserContext) -ne $($WAUConfig.WAU_UserContext))) {
                #Get-ScheduledTask -TaskName "Winget-AutoUpdate-UserContext" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
                New-ItemProperty $regPath -Name WAU_UserContext -Value $($WAUPolicies.WAU_UserContext) -PropertyType DWord -Force | Out-Null
                # Settings for the scheduled task in User context
                $taskAction = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\winget-upgrade.ps1`"`""
                $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
                $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00

                # Set up the task for user apps
                $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
                Register-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -InputObject $task -Force | Out-Null
                $ChangedSettings++
            }
            elseif ($null -eq $($WAUPolicies.WAU_UserContext) -and ($($WAUConfig.WAU_UserContext) -or $($WAUConfig.WAU_UserContext) -eq 0)) {
                Remove-ItemProperty $regPath -Name WAU_UserContext -Force -ErrorAction SilentlyContinue | Out-Null
                Get-ScheduledTask -TaskName "Winget-AutoUpdate-UserContext" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
                $ChangedSettings++
            }

            if ($ChangedSettings -gt 0) {
                Write-Log "Changed settings: $ChangedSettings" "Yellow"
            }
            #Get WAU Configurations after Policies change
            $Script:WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
        }
    }

    Return
}
