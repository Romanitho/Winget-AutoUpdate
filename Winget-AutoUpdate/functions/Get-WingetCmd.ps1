Function Get-WingetCmd {
    #Get WinGet Path (if admin context)
    $ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe"
    if ($ResolveWingetPath){
        #If multiple version, pick last one
        $WingetPath = $ResolveWingetPath[-1].Path
    }

    #Get Winget Location in User context
    $WingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($WingetCmd){
        $Script:Winget = $WingetCmd.Source
    }
    #Get Winget Location in System context (WinGet < 1.17)
    elseif (Test-Path "$WingetPath\AppInstallerCLI.exe"){
        $Script:Winget = "$WingetPath\AppInstallerCLI.exe"
    }
    #Get Winget Location in System context (WinGet > 1.17)
    elseif (Test-Path "$WingetPath\winget.exe"){
        $Script:Winget = "$WingetPath\winget.exe"
    }
    else{
        Write-Log "Winget not installed or detected !" "Red"
        return $false
    }

    #Run winget to list apps and accept source agrements (necessary on first run)
    & $Winget list --accept-source-agreements | Out-Null

    #Log Winget installed version
    $WingerVer = & $Winget --version
    Write-Log "Winget Version: $WingerVer"
    return $true
}