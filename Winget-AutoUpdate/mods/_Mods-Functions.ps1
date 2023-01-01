#Common shared functions for mods handling

function Stop-ModsProc ($Proc) {
    foreach ($process in $Proc)
    {
        Stop-Process -Name $process -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Return
}
function Wait-ModsProc ($Wait) {
    foreach ($process in $Wait)
    {
        Get-Process $process -ErrorAction SilentlyContinue | Foreach-Object { $_.WaitForExit() }
    }
    Return
}
function Uninstall-ModsApp ($App) {
    $InstalledSoftware = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    foreach ($obj in $InstalledSoftware){
        if ($obj.GetValue('DisplayName') -like $App) {
            $UninstallString = $obj.GetValue('UninstallString')
            $CleanedUninstallString = $UninstallString.Trim([char]0x0022)
            if ($UninstallString -like "MsiExec.exe*") {
                $ProductCode = Select-String "{.*}" -inputobject $UninstallString
                $ProductCode = $ProductCode.matches.groups[0].value
                #MSI x64 Installer
                $Exec = Start-Process "C:\Windows\System32\msiexec.exe" -ArgumentList "/x$ProductCode REBOOT=R /qn" -PassThru -Wait
                #Stop Hard Reboot (if bad MSI!)
                if ($Exec.ExitCode -eq 1641) {
                    Start-Process "C:\Windows\System32\shutdown.exe" -ArgumentList "/a"
                }
            }
            else {
                $QuietUninstallString = $obj.GetValue('QuietUninstallString')
                if ($QuietUninstallString) {
                    $QuietUninstallString = Select-String "(\x22.*\x22) +(.*)" -inputobject $QuietUninstallString
                    $Command = $QuietUninstallString.matches.groups[1].value
                    $Parameter = $QuietUninstallString.matches.groups[2].value
                    #All EXE x64 Installers (already defined silent uninstall)
                    Start-Process $Command -ArgumentList $Parameter -Wait
                }
                else {
                    if ((Test-Path $CleanedUninstallString)) {
                        $NullSoft = Select-String -Path $CleanedUninstallString -Pattern "Nullsoft"
                    }
                    if ($NullSoft) {
                        #NSIS x64 Installer
                        Start-Process $UninstallString -ArgumentList "/S" -Wait
                    }
                    else {
                        if ((Test-Path $CleanedUninstallString)) {
                            $Inno = Select-String -Path $CleanedUninstallString -Pattern "Inno Setup"
                        }
                        if ($Inno) {
                            #Inno x64 Installer
                            Start-Process $UninstallString -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" -Wait
                        }
                        else {
                            Write-Host "x64 Uninstaller unknown, trying the UninstallString from registry..."
                            $NativeUninstallString = Select-String "(\x22.*\x22) +(.*)" -inputobject $UninstallString
                            $Command = $NativeUninstallString.matches.groups[1].value
                            $Parameter = $NativeUninstallString.matches.groups[2].value
                            #All EXE x64 Installers (native defined uninstall)
                            Start-Process $Command -ArgumentList $Parameter -Wait
                        }
                    }
                }
            }
            $x64 = $true
            break
        }
    }
    if (!$x64) {
        $InstalledSoftware = Get-ChildItem "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        foreach ($obj in $InstalledSoftware){
            if ($obj.GetValue('DisplayName') -like $App) {
                $UninstallString = $obj.GetValue('UninstallString')
                $CleanedUninstallString = $UninstallString.Trim([char]0x0022)
                if ($UninstallString -like "MsiExec.exe*") {
                    $ProductCode = Select-String "{.*}" -inputobject $UninstallString
                    $ProductCode = $ProductCode.matches.groups[0].value
                    #MSI x86 Installer
                    $Exec = Start-Process "C:\Windows\System32\msiexec.exe" -ArgumentList "/x$ProductCode REBOOT=R /qn" -PassThru -Wait
                    #Stop Hard Reboot (if bad MSI!)
                    if ($Exec.ExitCode -eq 1641) {
                        Start-Process "C:\Windows\System32\shutdown.exe" -ArgumentList "/a"
                    }
                }
                else {
                    $QuietUninstallString = $obj.GetValue('QuietUninstallString')
                    if ($QuietUninstallString) {
                        $QuietUninstallString = Select-String "(\x22.*\x22) +(.*)" -inputobject $QuietUninstallString
                        $Command = $QuietUninstallString.matches.groups[1].value
                        $Parameter = $QuietUninstallString.matches.groups[2].value
                        #All EXE x86 Installers (already defined silent uninstall)
                        Start-Process $Command -ArgumentList $Parameter -Wait
                    }
                    else {
                        if ((Test-Path $CleanedUninstallString)) {
                            $NullSoft = Select-String -Path $CleanedUninstallString -Pattern "Nullsoft"
                        }
                        if ($NullSoft) {
                            #NSIS x86 Installer
                            Start-Process $UninstallString -ArgumentList "/S" -Wait
                        }
                        else {
                            if ((Test-Path $CleanedUninstallString)) {
                                $Inno = Select-String -Path $CleanedUninstallString -Pattern "Inno Setup"
                            }
                            if ($Inno) {
                                #Inno x86 Installer
                                Start-Process $UninstallString -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" -Wait
                            }
                            else {
                                Write-Host "x86 Uninstaller unknown, trying the UninstallString from registry..."
                                $NativeUninstallString = Select-String "(\x22.*\x22) +(.*)" -inputobject $UninstallString
                                $Command = $NativeUninstallString.matches.groups[1].value
                                $Parameter = $NativeUninstallString.matches.groups[2].value
                                #All EXE x86 Installers (native defined uninstall)
                                Start-Process $Command -ArgumentList $Parameter -Wait
                            }
                        }
                    }
                }
                break
            }
        }
    }
    Return
}
function Remove-ModsLnk ($Lnk) {
    foreach ($link in $Lnk)
    {
        Remove-Item -Path "${env:Public}\Desktop\$link.lnk" -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Return
}
