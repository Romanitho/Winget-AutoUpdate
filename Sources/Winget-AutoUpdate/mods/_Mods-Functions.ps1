#Common shared functions to handle the mods

function Invoke-ModsApp ($Run, $RunSwitch, $RunWait, $User) {
    if (Test-Path "$Run") {
        if (!$RunSwitch) { $RunSwitch = " " }
        if (!$User) {
            if (!$RunWait) {
                Start-Process $Run -ArgumentList $RunSwitch
            }
            else {
                Start-Process $Run -ArgumentList $RunSwitch -Wait
            }
        }
        else {
            Start-Process explorer $Run
        }
    }
    Return
}

function Skip-ModsProc ($Skip) {
    foreach ($process in $Skip) {
        $running = Get-Process -Name $process -ErrorAction SilentlyContinue
        if ($running) {
            Return $false
        }
    }
    Return
}

function Stop-ModsProc ($Proc) {
    foreach ($process in $Proc) {
        Stop-Process -Name $process -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Return
}

function Stop-ModsSvc ($Svc) {
    foreach ($service in $Svc) {
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Return
}

function Wait-ModsProc ($Wait) {
    foreach ($process in $Wait) {
        Get-Process $process -ErrorAction SilentlyContinue | Foreach-Object { $_.WaitForExit() }
    }
    Return
}

function Install-WingetID ($WingetIDInst) {
    foreach ($app in $WingetIDInst) {
        & $Winget install --id $app -e --accept-package-agreements --accept-source-agreements -s winget -h
    }
    Return
}

function Uninstall-WingetID ($WingetIDUninst) {
    foreach ($app in $WingetIDUninst) {
        & $Winget uninstall --id $app -e --accept-source-agreements -s winget -h
    }
    Return
}

function Uninstall-ModsApp ($AppUninst, $AllVersions) {
    foreach ($app in $AppUninst) {
        # we start from scanning the x64 node in registry, if something was found, then we set x64=TRUE
        [bool]$app_was_x64 = Get-InstalledSoftware -app $app -x64 $true;

        # if nothing was found in x64 node, then we repeat that action in x86 node
        if (!$app_was_x64) {
            Get-InstalledSoftware -app $app | Out-Null;
        }
    }
    Return
}

Function Get-InstalledSoftware() {
    [OutputType([Bool])]
    Param(
        [parameter(Mandatory = $true)] [string]$app,
        [parameter(Mandatory = $false)][bool]  $x64 = $false
    )
    if ($true -eq $x64) {
        [string]$path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall";
    }
    else {
        [string]$path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall";
    }

    [bool]$app_was_found = $false;
    [Microsoft.Win32.RegistryKey[]]$InstalledSoftware = Get-ChildItem $path;
    foreach ($obj in $InstalledSoftware) {
        if ($obj.GetValue('DisplayName') -like $App) {
            $UninstallString = $obj.GetValue('UninstallString')
            $CleanedUninstallString = $UninstallString.Replace('"', '')
            $ExeString = $CleanedUninstallString.Substring(0, $CleanedUninstallString.IndexOf('.exe') + 4)
            if ($UninstallString -like "MsiExec.exe*") {
                $ProductCode = Select-String "{.*}" -inputobject $UninstallString
                $ProductCode = $ProductCode.matches.groups[0].value
                # MSI Installer
                $Exec = Start-Process "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/x$ProductCode REBOOT=R /qn" -PassThru -Wait
                # Stop Hard Reboot (if bad MSI!)
                if ($Exec.ExitCode -eq 1641) {
                    Start-Process "$env:SystemRoot\System32\shutdown.exe" -ArgumentList "/a"
                }
            }
            else {
                $QuietUninstallString = $obj.GetValue('QuietUninstallString')
                if ($QuietUninstallString) {
                    $QuietUninstallString = Select-String '("[^"]*") +(.*)' -inputobject $QuietUninstallString
                    $Command = $QuietUninstallString.matches.groups[1].value
                    $Parameter = $QuietUninstallString.matches.groups[2].value
                    # All EXE Installers (already defined silent uninstall)
                    Start-Process $Command -ArgumentList $Parameter -Wait
                }
                else {
                    # Improved detection logic
                    if ((Test-Path $ExeString -ErrorAction SilentlyContinue)) {
                        try {
                            # Read the whole file to find installer signatures
                            $fileContent = Get-Content -Path $ExeString -Raw -ErrorAction Stop
                            # Executes silent uninstallation based on installer type
                            if ($fileContent -match "\bNullsoft\b" -or $fileContent -match "\bNSIS\b") {
                                # Nullsoft (NSIS) Uninstaller
                                Start-Process $ExeString -ArgumentList "/NCRC /S" -Wait
                            }
                            elseif ($fileContent -match "\bInno Setup\b") {
                                # Inno Uninstaller
                                Start-Process $ExeString -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" -Wait
                            }
                            elseif ($fileContent -match "\bWise Solutions\b") {
                                # Wise Uninstaller (Unwise32.exe)
                                # Find the Install.log path parameter in the UninstallString
                                $ArgString = $CleanedUninstallString.Substring($CleanedUninstallString.IndexOf('.exe') + 4).Trim()
                                # Copy files to temp folder so that Unwise32.exe can find Install.log (very, very old system)
                                Copy-Item -Path $ExeString -Destination $env:TEMP -Force
                                $ExeString = Join-Path $env:TEMP (Split-Path $ExeString -Leaf)
                                Copy-Item -Path $ArgString -Destination $env:TEMP -Force
                                $ArgString = Join-Path $env:TEMP (Split-Path $ArgString -Leaf)
                                # Execute the uninstaller with the copied Unwise32.exe
                                Start-Process $ExeString -ArgumentList "/s $ArgString" -Wait
                                # Remove the copied Unwise32.exe from temp folder (Install.log gets deleted by Unwise32.exe)
                                Remove-Item -Path $ExeString -Force -ErrorAction SilentlyContinue
                            }
                            else {
                                Write-Host "$(if($true -eq $x64) {'x64'} else {'x86'}) Uninstaller unknown, trying the UninstallString from registry..."
                                $NativeUninstallString = Select-String "(\x22.*\x22) +(.*)" -inputobject $UninstallString
                                $Command = $NativeUninstallString.matches.groups[1].value
                                $Parameter = $NativeUninstallString.matches.groups[2].value
                                Start-Process $Command -ArgumentList $Parameter -Wait
                            }
                        }
                        catch {
                            Write-Warning "Could not read installer file: $_"
                            # Fallback to standard method
                            Write-Host "Failed to inspect installer, trying UninstallString directly..."
                            $NativeUninstallString = Select-String "(\x22.*\x22) +(.*)" -inputobject $UninstallString
                            $Command = $NativeUninstallString.matches.groups[1].value
                            $Parameter = $NativeUninstallString.matches.groups[2].value
                            Start-Process $Command -ArgumentList $Parameter -Wait
                        }
                    }
                }
            }
            $app_was_found = $true
            if (!$AllVersions) {
                break
            }
        }
    }
    return $app_was_found;
}

function Remove-ModsLnk ($Lnk) {
    $removedCount = 0
    foreach ($link in $Lnk) {
        $linkPath = "${env:Public}\Desktop\$link.lnk"
        if (Test-Path $linkPath) {
            Remove-Item -Path $linkPath -Force -ErrorAction SilentlyContinue | Out-Null
            $removedCount++
        }
    }
    Return $removedCount
}

function Add-ModsReg ($AddKey, $AddValue, $AddTypeData, $AddType) {
    if ($AddKey -like "HKEY_LOCAL_MACHINE*") {
        $AddKey = $AddKey.replace("HKEY_LOCAL_MACHINE", "HKLM:")
    }
    if (!(Test-Path "$AddKey")) {
        New-Item $AddKey -Force -ErrorAction SilentlyContinue | Out-Null
    }
    New-ItemProperty $AddKey -Name $AddValue -Value $AddTypeData -PropertyType $AddType -Force | Out-Null
    Return
}

function Remove-ModsReg ($DelKey, $DelValue) {
    if ($DelKey -like "HKEY_LOCAL_MACHINE*") {
        $DelKey = $DelKey.replace("HKEY_LOCAL_MACHINE", "HKLM:")
    }
    if (Test-Path "$DelKey") {
        if (!$DelValue) {
            Remove-Item $DelKey -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
        else {
            Remove-ItemProperty $DelKey -Name $DelValue -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Return
}

function Remove-ModsFile ($DelFile) {
    foreach ($file in $DelFile) {
        if (Test-Path "$file") {
            Remove-Item -Path $file -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Return
}

function Rename-ModsFile ($RenFile, $NewName) {
    if (Test-Path "$RenFile") {
        Rename-Item -Path $RenFile -NewName $NewName -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Return
}

function Copy-ModsFile ($CopyFile, $CopyTo) {
    if (Test-Path "$CopyFile") {
        Copy-Item -Path $CopyFile -Destination $CopyTo -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Return
}

function Edit-ModsFile ($File, $FindText, $ReplaceText) {
    if (Test-Path "$File") {
        ((Get-Content -path $File -Raw) -replace "$FindText", "$ReplaceText") | Set-Content -Path $File -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Return
}

function Grant-ModsPath ($GrantPath) {
    foreach ($path in $GrantPath) {
        if (Test-Path "$path") {
            $NewAcl = Get-Acl -Path $path
            $identity = New-Object System.Security.Principal.SecurityIdentifier S-1-5-11
            if ((Get-Item $path) -is [System.IO.DirectoryInfo]) {
                $fileSystemAccessRuleArgumentList = $identity, 'Modify', 'ContainerInherit, ObjectInherit', 'None', 'Allow'
            }
            else {
                $fileSystemAccessRuleArgumentList = $identity, 'Modify', 'Allow'
            }
            $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
            $NewAcl.SetAccessRule($fileSystemAccessRule)

            # Grant delete permissions to subfolders and files
            $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
            $propagationFlag = [System.Security.AccessControl.PropagationFlags]::InheritOnly
            $deleteAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $identity, 'Delete', $inheritanceFlag, $propagationFlag, 'Allow'
            $NewAcl.AddAccessRule($deleteAccessRule)


            Set-Acl -Path $path -AclObject $NewAcl
        }
    }
    Return
}
