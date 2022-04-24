#Function to get WAU Configs

function Get-WAUConfig{
    
    #Get config file
    [xml]$WAUConfig = Get-Content "$WorkingDir\config\config.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
    
    #Check if WAU is configured for Black or White List
    if ($true -eq [System.Convert]::ToBoolean($WAUConfig.app.UseWAUWhiteList)){
        $Script:UseWhiteList = $true
    }
    else{
        $Script:UseWhiteList = $false
    }

    #Get Notification Level
    if ($WAUConfig.app.NotificationLevel){
        $Script:NotificationLevel = $WAUConfig.app.NotificationLevel
    }
    else{
        #Default: Full
        $Script:NotificationLevel = $full
    }
    
}
