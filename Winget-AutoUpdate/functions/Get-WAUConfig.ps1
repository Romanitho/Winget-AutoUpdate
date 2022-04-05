function Get-WAUConfig{
    
    [xml]$WAUConfig = Get-Content "$WorkingDir\config\config.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
    
    #Check if WAU is configured for Black or White List
    if ($true -eq [System.Convert]::ToBoolean($WAUConfig.app.UseWAUWhiteList)){
        Write-Log "WAU uses White List config"
        $Script:UseWhiteList = $true
    }
    else{
        Write-Log "WAU uses Black List config"
        $Script:UseWhiteList = $false
    }
}