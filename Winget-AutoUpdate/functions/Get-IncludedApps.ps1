#Function to get White List apps

function Get-IncludedApps {

    if (Test-Path "$WorkingDir\included_apps.txt") {

        return (Get-Content -Path "$WorkingDir\included_apps.txt").Trim() | Where-Object{$_.length -gt 0}
    
    }

}
