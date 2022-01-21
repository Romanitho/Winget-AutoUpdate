function Init {
    #Var
    $Script:WorkingDir = $PSScriptRoot

    #Logs initialisation
    $LogPath = "$WorkingDir\logs"
    if (!(Test-Path $LogPath)){
        New-Item -ItemType Directory -Force -Path $LogPath
    }

    #Log file
    $Script:LogFile = "$LogPath\updates.log"

    #Log Header
    $Log = "##################################################`n#     CHECK FOR APP UPDATES - $(Get-Date -Format 'dd/MM/yyyy')`n##################################################"
    $Log | Write-host
    $Log | out-file -filepath $LogFile -Append

    #Get locale file for Notification
    #Default en-US
    $DefaultLocal = "$WorkingDir\locale\en-US.xml"
    #Get OS locale
    $Locale = Get-WinSystemLocale
    #Test if OS locale config file exists
    $LocalFile = "$WorkingDir\locale\$($locale.Name).xml"
    if(Test-Path $LocalFile){
        [xml]$Script:NotifLocal = Get-Content $LocalFile -Encoding UTF8 -ErrorAction SilentlyContinue
        Write-Log "Local : $($locale.Name)"
    }
    else{
        [xml]$Script:NotifLocal = Get-Content $DefaultLocal -Encoding UTF8 -ErrorAction SilentlyContinue
        Write-Log "Local : en-US"
    } 
}

function Write-Log ($LogMsg,$LogColor = "White") {
    #Get log
    $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    #Echo log
    $Log | Write-host -ForegroundColor $LogColor
    #Write log to file
    $Log | out-file -filepath $LogFile -Append
}

function Start-NotifTask ($Title,$Message,$MessageType,$Balise) {    

    #Add XML variables
[xml]$ToastTemplate = @"
<toast launch="ms-get-started://redirect?id=apps_action">
    <visual>
        <binding template="ToastImageAndText03">
            <text id="1">$Title</text>
            <text id="2">$Message</text>
            <image id="1" src="$WorkingDir\icons\$MessageType.png" />
        </binding>
    </visual>
    <tag>$Balise</tag>
</toast>
"@

    #Save XML File
    $ToastTemplate.Save("$WorkingDir\notif.xml")

    #Send Notification to user
    Get-ScheduledTask -TaskName "Winget Update Notify" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
    #Wait for notification to display
    while ((Get-ScheduledTask -TaskName "Winget Update Notify").State  -ne 'Ready') {
        Write-Output "Waiting on scheduled task..."
        Start-Sleep 3
    }
}

function Test-Network {
    $timeout = 0
    $ping = $false
    #test connectivity during 30 min then timeout
    Write-Log "Checking internet connection..." "Yellow"
    while (!$ping -and $timeout -lt 1800){
        try{
            Invoke-RestMethod -Uri "https://ifconfig.me/"
            Write-Log "Coonected !" "Green"
            $ping = $true
            return 
        }
        catch{
            Start-Sleep 10
            $timeout += 10
            Write-Log "Checking internet connection. $($timeout)s." "Yellow"
        }
        if ($timeout -eq 300){            
            #Send Notif if no connection for 5 min
            Write-Log "Notify 'No connection'" "Yellow"
            $Title = $NotifLocal.local.outputs.output[0].title
            $Message = $NotifLocal.local.outputs.output[0].message
            $MessageType = "warning"
            $Balise = "connection"
            n $Title $Message $MessageType $Balise
        }
    }
    return $ping
}

function Get-WingetOutdated {
    class Software {
        [string]$Name
        [string]$Id
        [string]$Version
        [string]$AvailableVersion
    }

    #Get WinGet Location to run as system
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
        Write-Log "No Winget installed !"
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
    $lines = $upgradeResult.Split([Environment]::NewLine)

    # Find the line that starts with "------"
    $fl = 0
    while (-not $lines[$fl].StartsWith("-----"))
    {
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
    For ($i = $fl + 2; $i -le $lines.Length; $i++) 
    {
        $line = $lines[$i]
        if ($line.Length -gt ($availableStart + 1) -and -not $line.StartsWith('-'))
        {
            $name = $line.Substring(0, $idStart).TrimEnd()
            $id = $line.Substring($idStart, $versionStart - $idStart).TrimEnd()
            $version = $line.Substring($versionStart, $availableStart - $versionStart).TrimEnd()
            $available = $line.Substring($availableStart, $sourceStart - $availableStart).TrimEnd()
            $software = [Software]::new()
            $software.Name = $name;
            $software.Id = $id;
            $software.Version = $version
            $software.AvailableVersion = $available;
            $upgradeList += $software
        }
    }

    return $upgradeList
}

function Get-ExcludedApps{
    if (Test-Path "$WorkingDir\excluded_apps.txt"){
        return Get-Content -Path "$WorkingDir\excluded_apps.txt"
    }
}

### MAIN ###

#Run initialisation
Init

#Check network connectivity
$ping = Test-Network

if ($ping){

    #Get exclude apps list
    $toSkip = Get-ExcludedApps

    #Get outdated Winget packages
    Write-Log "Checking available updates..." "yellow"
    $outdated = Get-WingetOutdated

    #Log list of app to update
    foreach ($app in $outdated){
        #List available updates
        $Log = "Available update : $($app.Name). Current version : $($app.Version). Available version : $($app.AvailableVersion)."
        $Log | Write-host
        $Log | out-file -filepath $LogFile -Append
    }
    
    #Count good update installs
    $InstallOK = 0

    #For each app, notify and update
    foreach ($app in $outdated){

        if (-not ($toSkip -contains $app.Id)){

            #Send available update notification
            Write-Log "Updating $($app.Name) from $($app.Version) to $($app.AvailableVersion)..." "Cyan"
            $Title = $NotifLocal.local.outputs.output[2].title -f $($app.Name)
            $Message = $NotifLocal.local.outputs.output[2].message -f $($app.Version), $($app.AvailableVersion)
            $MessageType = "info"
            $Balise = $($app.Name)
            n $Title $Message $MessageType $Balise

            #Install update
            $Log = "#--- Winget - $($app.Name) Upgrade Starts ---"
            $Log | Write-host -ForegroundColor Gray
            $Log | out-file -filepath $LogFile -Append

            #Winget upgrade
            & $upgradecmd upgrade -e --id $($app.Id) --accept-package-agreements --accept-source-agreements -h
            Start-Sleep 3

            $Log = "#--- Winget - $($app.Name) Upgrade Finished ---"
            $Log | Write-host -ForegroundColor Gray
            $Log | out-file -filepath $LogFile -Append

            #Check installed version
            $checkoutdated = Get-WingetOutdated
            $FailedToUpgrade = $false
            foreach ($checkapp in $checkoutdated){
                if ($($checkapp.Id) -eq $($app.Id)) {
                    $FailedToUpgrade = $true
                }      
            }

            #Notify installation
            if ($FailedToUpgrade -eq $false){   
                #Send success updated app notification
                Write-Log "$($app.Name) updated to $($app.AvailableVersion) !" "Green"
                
                #Send Notif
                $Title = $NotifLocal.local.outputs.output[3].title -f $($app.Name)
                $Message = $NotifLocal.local.outputs.output[3].message -f $($app.AvailableVersion)
                $MessageType = "success"
                $Balise = $($app.Name)
                n $Title $Message $MessageType $Balise

                $InstallOK += 1
            }
            else {
                #Send failed updated app notification
                Write-Log "$($app.Name) update failed." "Red"
                
                #Send Notif
                $Title = $NotifLocal.local.outputs.output[4].title -f $($app.Name)
                $Message = $NotifLocal.local.outputs.output[4].message
                $MessageType = "error"
                $Balise = $($app.Name)
                n $Title $Message $MessageType $Balise
            }
		        }
        else{
            Write-Log "$($app.Name) : Skipped upgrade because it is in the excluded app list" "Gray"
        }
    }

    if ($InstallOK -gt 0){
        Write-Log "$InstallOK apps updated ! No more update." "Green"
    }
    if ($InstallOK -eq 0){
        Write-Log "No new update." "Green"
    }
}
else{
    Write-Log "Timeout. No internet connection !" "Red"
    #Send Notif
    $Title = $NotifLocal.local.outputs.output[1].title
    $Message = $NotifLocal.local.outputs.output[1].message
    $MessageType = "error"
    $Balise = "connection"
    n $Title $Message $MessageType $Balise
}
Write-Log "End of process!" "Cyan"