#Function to ask user consent before updating apps

function Invoke-UserApproval ($outdated){

    #Create / Update WAU Class for notification action
    if ($IsSystem) {
        $WAUClass = "HKLM:\Software\Classes\WAU"
        $WAUClassCmd = "$WAUClass\shell\open\command"
        $WAUClassRun = "Wscript.exe ""$WorkingDir\Invisible.vbs"" ""powershell.exe -NoProfile -ExecutionPolicy Bypass  -Command & '$WorkingDir\User-Run.ps1' -NotifApproved %1"""
        New-Item $WAUClassCmd -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -LiteralPath $WAUClass -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -LiteralPath $WAUClass -Name '(default)' -Value "URL:$($ActionType)" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -LiteralPath $WAUClass -Name 'EditFlags' -Value '2162688' -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -LiteralPath $WAUClassCmd -Name '(default)' -Value $WAUClassRun -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
        $Button1Action = "wau:system"
        $OnClickAction = "wau:systemDialogBox"
    }
    else{
        $Button1Action = "wau:user"
        $OnClickAction = "wau:userDialogBox"
    }

    $OutdatedApps = @()
    #If White List
    if ($WAUConfig.WAU_UseWhiteList -eq 1) {
        $toUpdate = Get-IncludedApps
        foreach ($app in $Outdated) {
            if (($toUpdate -contains $app.Id) -and $($app.Version) -ne "Unknown") {
                $OutdatedApps += "- $($app.Name)"
            }
        }
    }
    #If Black List or default
    else {
        $toSkip = Get-ExcludedApps
        foreach ($app in $Outdated) {
            if (-not ($toSkip -contains $app.Id) -and $($app.Version) -ne "Unknown") {
                $OutdatedApps += "- $($app.Name)"
            }
        }
    }

    $body = $OutdatedApps | Out-String
    if ($body) {
        #Ask user to update apps
        $Message = "Do you want to update these apps ?"
        $body += "`nPlease save your work and close theses apps"
        $WAUNotifContent = "$WorkingDir\config\NotifContent.txt"
	    New-Item -Path $WAUNotifContent -ItemType File -Force | Out-Null
        Set-Content -Path $WAUNotifContent -Value $body
        Start-NotifTask -Title "New available updates" -Message $Message -Body $body -ButtonDismiss -Button1Text "Yes" -Button1Action $Button1Action -OnClickAction $OnClickAction -MessageType "info"
        Return 0
    }
    else {
        Return 1
    }

}