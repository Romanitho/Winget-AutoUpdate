<# FUNCTIONS #>

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
    $DefaultLocale = "$WorkingDir\locale\en-US.xml"
    #Get OS locale
    $Locale = Get-WinSystemLocale
    #Test if OS locale config file exists
    $LocaleFile = "$WorkingDir\locale\$($locale.Name).xml"
    if(Test-Path $LocaleFile){
        [xml]$Script:NotifLocale = Get-Content $LocaleFile -Encoding UTF8 -ErrorAction SilentlyContinue
        $LocaleNotif = "Notification Langugage : $($locale.Name)"
    }
    else{
        [xml]$Script:NotifLocale = Get-Content $DefaultLocale -Encoding UTF8 -ErrorAction SilentlyContinue
        $LocaleNotif = "Notification Langugage : en-US"
    }
    Write-Log $LocaleNotif "Cyan"
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
    $ToastTemplateLocation = "$env:ProgramData\Winget-AutoUpdate\"
    if (!(Test-Path $ToastTemplateLocation)){
        New-Item -ItemType Directory -Force -Path $ToastTemplateLocation
    }
    $ToastTemplate.Save("$ToastTemplateLocation\notif.xml")

    #Send Notification to user. First, check if script is run as admin (or system)
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
        #Run Notify scheduled task to notify conneted users
        Get-ScheduledTask -TaskName "Winget-AutoUpdate-Notify" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
    }
    #else, run as user
    else{
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$WorkingDir\winget-notify.ps1`"" -NoNewWindow -Wait
    }

    #Wait for notification to display
    Start-Sleep 3
}

function Test-Network {
    #init
    $timeout = 0
    $ping = $false

    #test connectivity during 30 min then timeout
    Write-Log "Checking internet connection..." "Yellow"
    while (!$ping -and $timeout -lt 1800){
        try{
            Invoke-RestMethod -Uri "https://api.github.com/zen"
            Write-Log "Connected !" "Green"
            $ping = $true
            return $ping
        }
        catch{
            Start-Sleep 10
            $timeout += 10
            Write-Log "Checking internet connection. $($timeout)s." "Yellow"
            #Send Notif if no connection for 5 min
            if ($timeout -eq 300){
                Write-Log "Notify 'No connection'" "Yellow"
                $Title = $NotifLocale.local.outputs.output[0].title
                $Message = $NotifLocale.local.outputs.output[0].message
                $MessageType = "warning"
                $Balise = "connection"
                Start-NotifTask $Title $Message $MessageType $Balise
            }
        }
    }
    Write-Log "Timeout. No internet connection !" "Red"
    #Send Notif if no connection for 30 min
    $Title = $NotifLocale.local.outputs.output[1].title
    $Message = $NotifLocale.local.outputs.output[1].message
    $MessageType = "error"
    $Balise = "connection"
    Start-NotifTask $Title $Message $MessageType $Balise
    return $ping
}

function Get-WingetOutdated {
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
            #check if Avalaible Version is > than Current Version (block "unknow" versions loop)
            if ([version]$software.AvailableVersion -gt [version]$software.Version){
                $upgradeList += $software
            }
        }
    }

    return $upgradeList
}

function Get-ExcludedApps{
    if (Test-Path "$WorkingDir\excluded_apps.txt"){
        return Get-Content -Path "$WorkingDir\excluded_apps.txt"
    }
}


<# MAIN #>

#Run initialisation
Init

#Check network connectivity
if (Test-Network){

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
            $Title = $NotifLocale.local.outputs.output[2].title -f $($app.Name)
            $Message = $NotifLocale.local.outputs.output[2].message -f $($app.Version), $($app.AvailableVersion)
            $MessageType = "info"
            $Balise = $($app.Name)
            Start-NotifTask $Title $Message $MessageType $Balise

            #Winget upgrade
            Write-Log "------ Winget - $($app.Name) Upgrade Starts ------" "Gray"
            & $upgradecmd upgrade --id $($app.Id) --all --accept-package-agreements --accept-source-agreements -h
            Write-Log "----- Winget - $($app.Name) Upgrade Finished -----" "Gray"   

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
                $Title = $NotifLocale.local.outputs.output[3].title -f $($app.Name)
                $Message = $NotifLocale.local.outputs.output[3].message -f $($app.AvailableVersion)
                $MessageType = "success"
                $Balise = $($app.Name)
                Start-NotifTask $Title $Message $MessageType $Balise

                $InstallOK += 1
            }
            else {
                #Send failed updated app notification
                Write-Log "$($app.Name) update failed." "Red"
                
                #Send Notif
                $Title = $NotifLocale.local.outputs.output[4].title -f $($app.Name)
                $Message = $NotifLocale.local.outputs.output[4].message
                $MessageType = "error"
                $Balise = $($app.Name)
                Start-NotifTask $Title $Message $MessageType $Balise
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

#End
Write-Log "End of process!" "Cyan"
Sleep 3
