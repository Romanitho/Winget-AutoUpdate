<# LOAD FUNCTIONS #>

#Get Working Dir
$Script:WorkingDir = $PSScriptRoot
#Get Functions
Get-ChildItem "$WorkingDir\functions" | ForEach-Object {. $_.FullName}


<# MAIN #>

#Run log initialisation function
Start-Init

#Get WAU Configurations
Get-WAUConfig

#Get Notif Locale function
Get-NotifLocale

#Check network connectivity
if (Test-Network){
    #Check if Winget is installed and get Winget cmd
    $TestWinget = Get-WingetCmd
    
    if ($TestWinget){
        #Get Current Version
        Get-WAUCurrentVersion
        #Check if WAU update feature is enabled
        Get-WAUUpdateStatus
        #If yes then check WAU update
        if ($true -eq $WAUautoupdate){
            #Get Available Version
            Get-WAUAvailableVersion
            #Compare
            if ([version]$WAUAvailableVersion -gt [version]$WAUCurrentVersion){
                #If new version is available, update it
                Write-Log "WAU Available version: $WAUAvailableVersion" "Yellow"
                Update-WAU
            }
            else{
                Write-Log "WAU is up to date." "Green"
            }
        }

        #Get White or Black list
        if ($UseWhiteList){
            Write-Log "WAU uses White List config"
            $toUpdate = Get-IncludedApps
        }
        else{
            Write-Log "WAU uses Black List config"
            $toSkip = Get-ExcludedApps
        }

        #Get outdated Winget packages
        $outdated = Get-WingetOutdatedApps

        #Log list of app to update
        foreach ($app in $outdated){
            #List available updates
            $Log = "Available update : $($app.Name). Current version : $($app.Version). Available version : $($app.AvailableVersion)."
            $Log | Write-host
            $Log | out-file -filepath $LogFile -Append
        }
        
        #Count good update installations
        $Script:InstallOK = 0

        #If White List
        if ($UseWhiteList){
            #For each app, notify and update
            foreach ($app in $outdated){
                if (($toUpdate -contains $app.Id) -and $($app.Version) -ne "Unknown"){
                    Update-App $app
                }
                #if current app version is unknown
                elseif($($app.Version) -eq "Unknown"){
                    Write-Log "$($app.Name) : Skipped upgrade because current version is 'Unknown'" "Gray"
                }
                #if app is in "excluded list"
                else{
                    Write-Log "$($app.Name) : Skipped upgrade because it is not in the included app list" "Gray"
                }
            }
        }
        #If Black List
        else{
            #For each app, notify and update
            foreach ($app in $outdated){
                if (-not ($toSkip -contains $app.Id) -and $($app.Version) -ne "Unknown"){
                    Update-App $app
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
        }
        
        if ($InstallOK -gt 0){
            Write-Log "$InstallOK apps updated ! No more update." "Green"
        }
        if ($InstallOK -eq 0){
            Write-Log "No new update." "Green"
        }
    }
}

#End
Write-Log "End of process!" "Cyan"
Start-Sleep 3