#Function to get Black List apps

function Get-ExcludedApps {

    if (Test-Path "$WorkingDir\excluded_apps.txt") {

        return (Get-Content -Path "$WorkingDir\excluded_apps.txt").Trim() | Where-Object { $_.length -gt 0 }

    }

}
