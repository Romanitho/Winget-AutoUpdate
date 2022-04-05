function Get-IncludedApps{
    if (Test-Path "$WorkingDir\included_apps.txt"){
        return Get-Content -Path "$WorkingDir\included_apps.txt"
    }
}