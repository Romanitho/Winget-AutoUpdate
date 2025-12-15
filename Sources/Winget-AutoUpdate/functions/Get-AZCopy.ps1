<#
.SYNOPSIS
    Downloads or updates AzCopy for Azure Blob storage operations.

.DESCRIPTION
    Checks for the latest version of AzCopy and downloads/updates it
    if a newer version is available. AzCopy is used for syncing mods
    from Azure Blob Storage.

.PARAMETER WingetUpdatePath
    The WAU installation directory where azcopy.exe will be stored.

.EXAMPLE
    Get-AZCopy "C:\Program Files\Winget-AutoUpdate"

.NOTES
    Downloads from Microsoft's official AzCopy distribution.
    Extracts and copies only the azcopy.exe executable.
#>
Function Get-AZCopy ($WingetUpdatePath) {

    # Get latest AzCopy version from Microsoft redirect
    $AZCopyLink = (Invoke-WebRequest -Uri https://aka.ms/downloadazcopy-v10-windows -UseBasicParsing -MaximumRedirection 0 -ErrorAction SilentlyContinue).headers.location
    $AZCopyVersionRegex = [regex]::new("(\d+\.\d+\.\d+)")
    $AZCopyLatestVersion = $AZCopyVersionRegex.Match($AZCopyLink).Value

    # Default to 0.0.0 if version detection fails
    if ($null -eq $AZCopyLatestVersion -or "" -eq $AZCopyLatestVersion) {
        $AZCopyLatestVersion = "0.0.0"
    }

    # Check current installed version
    if (Test-Path -Path "$WingetUpdatePath\azcopy.exe" -PathType Leaf) {
        $AZCopyCurrentVersion = & "$WingetUpdatePath\azcopy.exe" -v
        $AZCopyCurrentVersion = $AZCopyVersionRegex.Match($AZCopyCurrentVersion).Value
        Write-ToLog "AZCopy version $AZCopyCurrentVersion found"
    }
    else {
        Write-ToLog "AZCopy not already installed"
        $AZCopyCurrentVersion = "0.0.0"
    }

    # Download and install if newer version available
    if (([version] $AZCopyCurrentVersion) -lt ([version] $AZCopyLatestVersion)) {
        Write-ToLog "Installing version $AZCopyLatestVersion of AZCopy"

        # Download AzCopy zip
        Invoke-WebRequest -Uri $AZCopyLink -UseBasicParsing -OutFile "$WingetUpdatePath\azcopyv10.zip"
        Write-ToLog "Extracting AZCopy zip file"

        # Extract archive
        Expand-archive -Path "$WingetUpdatePath\azcopyv10.zip" -Destinationpath "$WingetUpdatePath" -Force

        # Find extracted folder (handles version-specific folder names)
        $AZCopyPathSearch = Resolve-Path -path "$WingetUpdatePath\azcopy_*"

        if ($AZCopyPathSearch -is [array]) {
            $AZCopyEXEPath = $AZCopyPathSearch[$AZCopyPathSearch.Length - 1]
        }
        else {
            $AZCopyEXEPath = $AZCopyPathSearch
        }

        # Copy executable to main folder
        Write-ToLog "Copying 'azcopy.exe' to main folder"
        Copy-Item "$AZCopyEXEPath\azcopy.exe" -Destination "$WingetUpdatePath\"

        # Cleanup temporary files
        Write-ToLog "Removing temporary AZCopy files"
        Remove-Item -Path $AZCopyEXEPath -Recurse
        Remove-Item -Path "$WingetUpdatePath\azcopyv10.zip"

        # Verify installation
        $AZCopyCurrentVersion = & "$WingetUpdatePath\azcopy.exe" -v
        $AZCopyCurrentVersion = $AZCopyVersionRegex.Match($AZCopyCurrentVersion).Value
        Write-ToLog "AZCopy version $AZCopyCurrentVersion installed"
    }
}
