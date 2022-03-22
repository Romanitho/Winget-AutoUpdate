function Get-WingetOutdatedApps {
    class Software {
        [string]$Name
        [string]$Id
        [string]$Version
        [string]$AvailableVersion
    }

    #Get WinGet Location
    $WingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($WingetCmd){
        $script:upgradecmd = $WingetCmd.Source
    }
    elseif (Test-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\AppInstallerCLI.exe"){
        #WinGet < 1.17
        $script:upgradecmd = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\AppInstallerCLI.exe" | Select-Object -ExpandProperty Path
    }
    elseif (Test-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"){
        #WinGet > 1.17
        $script:upgradecmd = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" | Select-Object -ExpandProperty Path
    }
    else{
        Write-Log "Winget not installed !"
        return
    }

    #Run winget to list apps and accept source agrements (necessary on first run)
    & $upgradecmd list --accept-source-agreements | Out-Null

    #Get list of available upgrades on winget format
    $upgradeResult = & $upgradecmd upgrade | Out-String

    #Start Convertion of winget format to an array. Check if "-----" exists
    if (!($upgradeResult -match "-----")){
        return
    }

    #Split winget output to lines
    $lines = $upgradeResult.Split([Environment]::NewLine).Replace("¦ ","")

    # Find the line that starts with "------"
    $fl = 0
    while (-not $lines[$fl].StartsWith("-----")){
        $fl++
    }
    
    #Get header line
    $fl = $fl - 2

    #Get header titles
    $index = $lines[$fl] -split '\s+'

    # Line $i has the header, we can find char where we find ID and Version
    $idStart = $lines[$fl].IndexOf($index[1])
    $versionStart = $lines[$fl].IndexOf($index[2])
    $availableStart = $lines[$fl].IndexOf($index[3])
    $sourceStart = $lines[$fl].IndexOf($index[4])

    # Now cycle in real package and split accordingly
    $upgradeList = @()
    For ($i = $fl + 2; $i -le $lines.Length; $i++){
        $line = $lines[$i]
        if ($line.Length -gt ($sourceStart+5) -and -not $line.StartsWith('-')){
            $software = [Software]::new()
            $software.Name = $line.Substring(0, $idStart).TrimEnd()
            $software.Id = $line.Substring($idStart, $versionStart - $idStart).TrimEnd()
            $software.Version = $line.Substring($versionStart, $availableStart - $versionStart).TrimEnd()
            $software.AvailableVersion = $line.Substring($availableStart, $sourceStart - $availableStart).TrimEnd()
            #add formated soft to list
            $upgradeList += $software
        }
    }

    return $upgradeList
}