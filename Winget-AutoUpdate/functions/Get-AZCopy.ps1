#Function to get AZCopy if it doesn't exist and update it if it does

Function Get-AZCopy ($WingetUpdatePath){

    $AZCopyLink = (Invoke-WebRequest -Uri https://aka.ms/downloadazcopy-v10-windows -MaximumRedirection 0 -ErrorAction SilentlyContinue).headers.location
    $AZCopyVersionRegex = [regex]::new("(\d+\.\d+\.\d+)")
    $AZCopyLatestVersion = $AZCopyVersionRegex.Match($AZCopyLink).Value

    if ($null -eq $AZCopyLatestVersion -or "" -eq $AZCopyLatestVersion) {
        $AZCopyLatestVersion = "0.0.0"
    }

    if (Test-Path -Path "$WingetUpdatePath\azcopy.exe" -PathType Leaf) {
        $AZCopyCurrentVersion = & "$WingetUpdatePath\azcopy.exe" -v
        $AZCopyCurrentVersion = $AZCopyVersionRegex.Match($AZCopyCurrentVersion).Value 
        Write-Log  "AZCopy version $AZCopyCurrentVersion found" 
    }
    else {
        Write-Log  "AZCopy not already installed" 
        $AZCopyCurrentVersion = "0.0.0"
    }

    if (([version] $AZCopyCurrentVersion) -lt ([version] $AZCopyLatestVersion)) {
        Write-Log  "Installing version $AZCopyLatestVersion of AZCopy"   
        Invoke-WebRequest -Uri $AZCopyLink -OutFile "$WingetUpdatePath\azcopyv10.zip"
        Write-Log  "Extracting AZCopy zip file"

        Expand-archive -Path "$WingetUpdatePath\azcopyv10.zip" -Destinationpath "$WingetUpdatePath" -Force

        $AZCopyPathSearch = Resolve-Path -path "$WingetUpdatePath\azcopy_*" 
    
        if ($AZCopyPathSearch -is [array]) {
            $AZCopyEXEPath = $AZCopyPathSearch[$AZCopyPathSearch.Length - 1]
        }
        else {
            $AZCopyEXEPath = $AZCopyPathSearch
        }

        Write-Log  "Copying 'azcopy.exe' to main folder"
        Copy-Item "$AZCopyEXEPath\azcopy.exe" -Destination "$WingetUpdatePath\"

        Write-Log  "Removing temporary AZCopy files"
        Remove-Item -Path $AZCopyEXEPath -Recurse
        Remove-Item -Path "$WingetUpdatePath\azcopyv10.zip"

        $AZCopyCurrentVersion = & "$WingetUpdatePath\azcopy.exe" -v
        $AZCopyCurrentVersion = $AZCopyVersionRegex.Match($AZCopyCurrentVersion).Value
        Write-Log  "AZCopy version $AZCopyCurrentVersion installed"
    }
}