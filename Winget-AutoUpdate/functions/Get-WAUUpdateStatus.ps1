function Get-WAUUpdateStatus{
    
    [xml]$UpdateStatus = Get-Content "$WorkingDir\config\config.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
    
    #Check if AutoUpdate is enabled
    if ($true -eq [System.Convert]::ToBoolean($UpdateStatus.app.WAUautoupdate)){
        Write-Log "WAU AutoUpdate is enabled" "Green"
        $Script:WAUautoupdate = $true
        
        #Check if pre-release versions are enabled
        if ($true -eq [System.Convert]::ToBoolean($UpdateStatus.app.WAUprerelease)){
            Write-Log "WAU AutoUpdate Pre-release enabled" "Cyan"
            $Script:WAUprerelease = $true
        }
        else{
            $Script:WAUprerelease = $false
        }
    }
    else{
        Write-Log "WAU AutoUpdate is Disabled" "Grey"
        $Script:WAUautoupdate = $false
    }
}