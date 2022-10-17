#Function to get Winget Command regarding execution context (User, System...)

Function Get-WingetCmd {

    #Get WinGet Path (if admin context)
    $ResolveWingetPath = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" | Sort-Object { [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1') }
    if ($ResolveWingetPath) {
        #If multiple version, pick last one
        $WingetPath = $ResolveWingetPath[-1].Path
    }

    #Get Winget Location in User context
    $WingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($WingetCmd) {
        $Script:Winget = $WingetCmd.Source
    }
    #Get Winget Location in System context
    elseif (Test-Path "$WingetPath\winget.exe") {
        $Script:Winget = "$WingetPath\winget.exe"
    }
    else {
        Write-Log "Winget not installed or detected !" "Red"
        return $false
    }

    #Run winget to list apps and accept source agrements (necessary on first run)
    & $Winget list --accept-source-agreements -s winget | Out-Null

    #Log Winget installed version
    $WingetVer = & $Winget --version
    Write-Log "Winget Version: $WingetVer"
    
    return $true

}
