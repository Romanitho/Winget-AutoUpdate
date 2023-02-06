#Function to ask user consent before updating apps

function Invoke-UserApproval ($outdated){

    #Create / Update WAU Class for notification action
    $WAUClass = "HKLM:\Software\Classes\WAU"
    $WAUClassCmd = "$WAUClass\shell\open\command"
    if ($IsSystem){
        $WAUClassRun = "Wscript.exe ""$WingetUpdatePath\Invisible.vbs"" ""powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$WingetUpdatePath\User-Run.ps1' -NotifApprovedAsSystem"
    }
    else{
        $WAUClassRun = "Wscript.exe ""$WingetUpdatePath\Invisible.vbs"" ""powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$WingetUpdatePath\User-Run.ps1' -NotifApprovedAsUser"
    }
    New-Item $WAUClassCmd -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath $WAUClass -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath $WAUClass -Name '(default)' -Value "URL:$($ActionType)" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath $WAUClass -Name 'EditFlags' -Value '2162688' -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath $WAUClassCmd -Name '(default)' -Value $WAUClassRun -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null

    $OutdatedApps = @()
    #If White List
    if ($WAUConfig.WAU_UseWhiteList -eq 1) {
        $toUpdate = Get-IncludedApps
        foreach ($app in $Outdated) {
            if (($toUpdate -contains $app.Id) -and $($app.Version) -ne "Unknown") {
                $OutdatedApps += $app.Name
            }
        }
    }
    #If Black List or default
    else {
        $toSkip = Get-ExcludedApps
        foreach ($app in $Outdated) {
            if (-not ($toSkip -contains $app.Id) -and $($app.Version) -ne "Unknown") {
                $OutdatedApps += $app.Name
            }
        }
    }

    $body = $OutdatedApps | Out-String
    if ($body) {
        #Ask user to update apps
        Start-NotifTask -Title "New available updates" -Message "Do you want to update these apps ?" -Body $body -ButtonDismiss -Button1Text "Yes" -Button1Action "wau:1" -MessageType "info"
        Return 0
    }
    else {
        Return 1
    }

}