function Init {
    #Var
    $Script:WorkingDir = "C:\ProgramData\winget-update"

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
}

function Write-Log ($LogMsg,$LogColor = "White") {
    #Get log
    $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    #Echo log
    $Log | Write-host -ForegroundColor $LogColor
    #Write log to file
    $Log | out-file -filepath $LogFile -Append
}

function Run-NotifTask ($Title,$Message,$MessageType,$Balise) {    

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
        echo "Waiting on scheduled task..."
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
            Write-Log "Connected !" "Green"
            $ping = $true
            return 
        }
        catch{
            sleep 10
            $timeout += 10
            Write-Log "Checking internet connection. $($timeout)s." "Yellow"
        }
        if ($timeout -eq 300){            
            #Send Notif if no connection for 5 min
            Write-Log "Notify 'No connection'" "Yellow"
            $Title = "Vérifiez votre connexion réseau"
            $Message = "Impossible de vérifier les mises à jour logicielles pour le moment !"
            $MessageType = "warning"
            $Balise = "connection"
            Run-NotifTask $Title $Message $MessageType $Balise
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
    if (Test-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\AppInstallerCLI.exe"){
        #WinGet < 1.17
        $script:upgradecmd = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\AppInstallerCLI.exe" | Select -ExpandProperty Path

    }
    elseif (Test-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"){
        #WinGet > 1.17
        $script:upgradecmd = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" | Select -ExpandProperty Path
    }
    else{
        Write-Log "No Winget installed !"
        return
    }

    $upgradeResult = & $upgradecmd upgrade --accept-source-agreements | Out-String

    if (!($upgradeResult -match "-----")){
        return
    }

    $lines = $upgradeResult.Split([Environment]::NewLine)

    # Find the line that starts with ------
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

### MAIN ###

#Run initialisation
Init

#Exclude apps (auto update)
$toSkip = @(
"Google.Chrome",
"Mozilla.Firefox",
"Microsoft.Edge",
"Microsoft.Office"
)

#Check network connectivity
$ping = Test-Network

if ($ping){

    #Get outdated choco packages
    Write-Log "Checking available updates..." "yellow"
    
    #Get outdated apps
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
            
            #Send Notif
            $Title = "$($app.Name) va être mis à jour."
            $Message = "$($app.Version) -> $($app.AvailableVersion)"
            $MessageType = "info"
            $Balise = $($app.Name)
            Run-NotifTask $Title $Message $MessageType $Balise

            #Install update
            $Log = "#--- Winget - $($app.Name) Upgrade Starts ---"
            $Log | Write-host -ForegroundColor Gray
            $Log | out-file -filepath $LogFile -Append

            #Winget upgrade
            & $upgradecmd upgrade -e --id $($app.Id) --accept-package-agreements --accept-source-agreements
            Sleep 3

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
                $Title = "$($app.Name) a été mis à jour."
                $Message = "Version installée : $($app.AvailableVersion)"
                $MessageType = "success"
                $Balise = $($app.Name)
                Run-NotifTask $Title $Message $MessageType $Balise

                $InstallOK += 1
            }
            else {
                #Send failed updated app notification
                Write-Log "$($app.Name) update failed." "Red"
                
                #Send Notif
                $Title = "$($app.Name) n'a pas pu être mis à jour !"
                $Message = "Contacter le support."
                $MessageType = "error"
                $Balise = $($app.Name)
                Run-NotifTask $Title $Message $MessageType $Balise
            }
		        }
        else{
            Write-Log "Skipped upgrade because $($app.Name) is in the excluded app list" "Gray"
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
    $Title = "Aucune connexion réseau"
    $Message = "Les mises à jour logicielles n'ont pas pu être vérifiées !"
    $MessageType = "error"
    $Balise = "connection"
    Run-NotifTask $Title $Message $MessageType $Balise
}
Write-Log "End of process!" "Cyan"
