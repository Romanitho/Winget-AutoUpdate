function Get-WAUUpdateStatus{
    #Get AutoUpdate status
    [xml]$UpdateStatus = Get-Content "$WorkingDir\config\config.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($true -eq $UpdateStatus.app.WAUautoupdate){
        Write-Log "WAU AutoUpdate is Enabled" "Green"
        return $true
    }
    else{
        Write-Log "WAU AutoUpdate is Disabled" "Grey"
        return $false
    }
}