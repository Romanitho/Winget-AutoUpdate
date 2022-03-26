<# LOAD FUNCTIONS #>

#Get Working Dir
$Script:WorkingDir = $PSScriptRoot
#Get Functions
Get-ChildItem "$WorkingDir\functions" | ForEach-Object {. $_.FullName}


<# MAIN #>

#Run log initialisation function
Start-Init

#Get Notif Locale function
Get-NotifLocale

#Check network connectivity
if (Test-Network){
    #Get Current Version
    Get-WAUCurrentVersion
    #Check if WAU update feature is enabled
    Get-WAUUpdateStatus
    #If yes then check WAU update
    if ($true -eq $WAUautoupdate){
        #Get Available Version
        Get-WAUAvailableVersion
        #Compare
        if ($WAUAvailableVersion -gt $WAUCurrentVersion){
            #If new version is available, update it
            Write-Log "WAU Current version: $WAUCurrentVersion - Available version: $WAUAvailableVersion" "Yellow"
            Update-WAU
        }
        else{
            Write-Log "WAU Current version : $WAUCurrentVersion - Up to date." "Green"
        }
    }

    #Get exclude apps list
    $toSkip = Get-ExcludedApps

    #Get outdated Winget packages
    Write-Log "Checking available updates..." "yellow"
    $outdated = Get-WingetOutdatedApps

    #Log list of app to update
    foreach ($app in $outdated){
        #List available updates
        $Log = "Available update : $($app.Name). Current version : $($app.Version). Available version : $($app.AvailableVersion)."
        $Log | Write-host
        $Log | out-file -filepath $LogFile -Append
    }
    
    #Count good update installations
    $InstallOK = 0

    #For each app, notify and update
    foreach ($app in $outdated){

        if (-not ($toSkip -contains $app.Id) -and $($app.Version) -ne "Unknown"){

            #Send available update notification
            Write-Log "Updating $($app.Name) from $($app.Version) to $($app.AvailableVersion)..." "Cyan"
            $Title = $NotifLocale.local.outputs.output[2].title -f $($app.Name)
            $Message = $NotifLocale.local.outputs.output[2].message -f $($app.Version), $($app.AvailableVersion)
            $MessageType = "info"
            $Balise = $($app.Name)
            Start-NotifTask $Title $Message $MessageType $Balise

            #Winget upgrade
            Write-Log "##########   WINGET UPGRADE PROCESS STARTS FOR APPLICATION ID '$($App.Id)'   ##########" "Gray"
                #Run Winget Upgrade command
                & $UpgradeCmd upgrade --id $($app.Id) --all --accept-package-agreements --accept-source-agreements -h | Tee-Object -file $LogFile -Append
                
                #Check if application updated properly
                $CheckOutdated = Get-WingetOutdatedApps
                $FailedToUpgrade = $false
                foreach ($CheckApp in $CheckOutdated){
                    if ($($CheckApp.Id) -eq $($app.Id)) {
                        #If app failed to upgrade, run Install command
                        & $upgradecmd install --id $($app.Id) --accept-package-agreements --accept-source-agreements -h | Tee-Object -file $LogFile -Append
                        #Check if application installed properly
                        $CheckOutdated2 = Get-WingetOutdatedApps
                        foreach ($CheckApp2 in $CheckOutdated2){
                            if ($($CheckApp2.Id) -eq $($app.Id)) {
                                $FailedToUpgrade = $true
                            }      
                        }
                    }
                }
            Write-Log "##########   WINGET UPGRADE PROCESS FINISHED FOR APPLICATION ID '$($App.Id)'   ##########" "Gray"   

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
        #if current app version is unknown
        elseif($($app.Version) -eq "Unknown"){
            Write-Log "$($app.Name) : Skipped upgrade because current version is 'Unknown'" "Gray"
        }
        #if app is in "excluded list"
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
Start-Sleep 3
