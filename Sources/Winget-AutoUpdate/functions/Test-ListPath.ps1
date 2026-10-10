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
    # Enable TLS 1.2 for secure connections
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 #DevSkim: ignore DS440020 Hard-coded SSL/TLS Protocol
        
    $ListType = if ($UseWhiteList) { "included_apps.txt" } else { "excluded_apps.txt" }
    $LocalList = Join-Path $WingetUpdatePath $ListType
    $dateLocal = $null
    if (Test-Path $LocalList) {
        $dateLocal = (Get-Item $LocalList).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    }

    # URL path: policy lists must remain HTTPS on every redirect.
    if ($ListPath -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
        if ($ListPath -notmatch '(?i)^https://') {
            Write-ToLog 'Insecure remote app-list URL rejected; use HTTPS.' 'Red'
            $Script:ReachNoPath = $true
            return $false
        }
        $parts = $ListPath -split '\?', 2
        $ExternalList = $parts[0].TrimEnd('/') + '/' + $ListType
        if ($parts.Count -eq 2) { $ExternalList += '?' + $parts[1] }

        try {
            $download = Save-WauHttpsFile -Uri $ExternalList -Destination $LocalList -OnlyIfNewer
            if (-not $download.HasLastModified) { $Script:AlwaysDownloaded = $true }
            return [bool]$download.Changed
        }
        catch {
            Write-ToLog 'Remote app-list download failed; check URL, TLS and network access.' 'Yellow'
            $Script:ReachNoPath = $true
            return $false
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
