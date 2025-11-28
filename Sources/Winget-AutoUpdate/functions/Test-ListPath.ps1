<#
.SYNOPSIS
    Syncs app list from external source.

.DESCRIPTION
    Downloads included/excluded apps list from URL, UNC, or local path if newer.

.PARAMETER ListPath
    External path (URL, UNC, or local).

.PARAMETER UseWhiteList
    True for included_apps.txt, false for excluded_apps.txt.

.PARAMETER WingetUpdatePath
    Local WAU installation directory.

.OUTPUTS
    Boolean: True if updated, False otherwise.
#>
function Test-ListPath ($ListPath, $UseWhiteList, $WingetUpdatePath) {

    $ListType = if ($UseWhiteList) { "included_apps.txt" } else { "excluded_apps.txt" }
    $LocalList = Join-Path $WingetUpdatePath $ListType
    $dateLocal = $null
    if (Test-Path $LocalList) {
        $dateLocal = (Get-Item $LocalList).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    }

    # URL path
    if ($ListPath -like "http*") {
        $ExternalList = "$ListPath/$ListType"

        # Handle SAS token URLs
        if ($ListPath -match "\?") {
            $parts = $ListPath.Split("?")
            $ExternalList = "$($parts[0])/$ListType`?$($parts[1])"
        }

        try {
            $wc = New-Object System.Net.WebClient
            $wc.OpenRead($ExternalList).Close() | Out-Null
            $dateExternal = ([DateTime]$wc.ResponseHeaders['Last-Modified']).ToString("yyyy-MM-dd HH:mm:ss")

            if (-not $dateLocal -or $dateExternal -gt $dateLocal) {
                $wc.DownloadFile($ExternalList, $LocalList)
                return $true
            }
        }
        catch {
            try {
                $wc.DownloadFile($ExternalList, $LocalList)
                $Script:AlwaysDownloaded = $true
                return $true
            }
            catch {
                $Script:ReachNoPath = $true
                return $false
            }
        }
    }
    # UNC or local path
    else {
        $ExternalList = Join-Path $ListPath $ListType
        if (Test-Path $ExternalList) {
            $dateExternal = (Get-Item $ExternalList).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            if (-not $dateLocal -or $dateExternal -gt $dateLocal) {
                Copy-Item $ExternalList -Destination $LocalList -Force
                return $true
            }
        }
        else {
            $Script:ReachNoPath = $true
            return $false
        }
    }
}
