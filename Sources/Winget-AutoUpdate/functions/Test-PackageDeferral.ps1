<#
.SYNOPSIS
    Tests whether an application update should be deferred based on its release date.

.DESCRIPTION
    Checks if a package's available update is within a deferral window.
    Supports both a global deferral period (WAU_DeferralDays) and per-app overrides
    via mods\<AppID>-deferral.txt.
    Supports local caching and a centralized network share cache (WAU_SharedCachePath)
    enabling a decentralized write-once peer-to-peer cache across enterprise clients.

.PARAMETER App
    Application object with Id, Name, Version, and AvailableVersion properties.

.PARAMETER Config
    WAU configuration object (from Get-WAUConfig).

.PARAMETER Source
    WinGet repository source (e.g., 'winget'). Defaults to 'winget'.

.PARAMETER WorkingDir
    The WAU root installation directory.

.PARAMETER SharedCachePath
    Optional path to a central network share cache. Defaults to $Config.WAU_SharedCachePath.

.OUTPUTS
    Boolean: $true if the update is deferred (should be skipped), $false otherwise.

.EXAMPLE
    if (Test-PackageDeferral -App $app -Config $WAUConfig -WorkingDir $WorkingDir) { continue }
#>
function Test-PackageDeferral {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $App,

        [Parameter(Mandatory = $false)]
        $Config = $Script:WAUConfig,

        [Parameter(Mandatory = $false)]
        [string]$Source = "winget",

        [Parameter(Mandatory = $false)]
        [string]$WorkingDir = $Script:WorkingDir,

        [Parameter(Mandatory = $false)]
        [string]$SharedCachePath = $null
    )

    if (-not $WorkingDir) {
        $WorkingDir = $PSScriptRoot
    }

    # Step 1: Determine deferral days (per-app mod takes precedence over global setting)
    $deferralDays = 0
    $isPerAppMod = $false

    $modDeferralPath = Join-Path $WorkingDir "mods\$($App.Id)-deferral.txt"
    if (Test-Path $modDeferralPath) {
        $modContent = Get-Content -Path $modDeferralPath -Raw -ErrorAction SilentlyContinue
        if ($modContent) {
            $parsedDays = 0
            if ([int]::TryParse($modContent.Trim(), [ref]$parsedDays)) {
                $deferralDays = $parsedDays
                $isPerAppMod = $true
            }
        }
    }

    if (-not $isPerAppMod -and $Config -and $Config.WAU_DeferralDays) {
        $parsedGlobalDays = 0
        if ([int]::TryParse($Config.WAU_DeferralDays.ToString().Trim(), [ref]$parsedGlobalDays)) {
            $deferralDays = $parsedGlobalDays
        }
    }

    # If deferral period is 0 or negative, deferral is inactive for this app
    if ($deferralDays -le 0) {
        return $false
    }

    # Step 2: Check source - only 'winget' community repository is hosted on microsoft/winget-pkgs
    if ($Source -ne "winget") {
        Write-ToLog "$($App.Name) : Source is '$Source' (not community winget). Deferral check skipped." "Gray"
        return $false
    }

    # Step 3: Setup local cache paths
    $localCacheDir = Join-Path $WorkingDir "cache"
    $localCacheFile = Join-Path $localCacheDir "deferral_cache.json"

    if (-not (Test-Path $localCacheDir)) {
        New-Item -ItemType Directory -Path $localCacheDir -Force -ErrorAction SilentlyContinue | Out-Null
    }

    # Setup shared cache path if configured
    if (-not $SharedCachePath -and $Config -and $Config.WAU_SharedCachePath) {
        $SharedCachePath = $Config.WAU_SharedCachePath.ToString().TrimEnd(" ", "\", "/")
    }

    $safeId = ($App.Id -replace '[^\w\.\-]', '_')
    $safeVersion = ($App.AvailableVersion -replace '[^\w\.\-]', '_')
    $sharedPkgFileName = "$safeId#$safeVersion.json"

    $sharedCacheAvailable = $false
    $sharedPkgFilePath = $null

    if ($SharedCachePath) {
        try {
            if (Test-Path -Path $SharedCachePath -ErrorAction Stop) {
                $sharedCacheAvailable = $true
                $sharedPkgFilePath = Join-Path $SharedCachePath $sharedPkgFileName
            }
            else {
                Write-ToLog "Shared cache path '$SharedCachePath' not found/accessible. Using local cache." "Yellow"
            }
        }
        catch {
            Write-ToLog "Warning: Could not access shared cache '$SharedCachePath': $_. Using local cache." "Yellow"
        }
    }

    $releaseDateUtc = $null

    # Step 3a: Check Shared Cache first (File-per-package-version write-once pattern)
    if ($sharedCacheAvailable -and (Test-Path $sharedPkgFilePath)) {
        try {
            $sharedJson = Get-Content -Path $sharedPkgFilePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
            if ($sharedJson -and $sharedJson.ReleaseDateUtc) {
                $releaseDateUtc = [DateTime]::Parse(
                    $sharedJson.ReleaseDateUtc,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
                )
                Write-ToLog "$($App.Name) : Found in shared cache." "Gray"
            }
        }
        catch {
            Write-Verbose "Could not read existing shared cache file '$sharedPkgFilePath': $_"
        }
    }

    # Step 3b: If not in shared cache, check Local Cache
    $localCache = @{}
    if (-not $releaseDateUtc) {
        if (Test-Path $localCacheFile) {
            try {
                $cacheContent = Get-Content -Path $localCacheFile -Raw -Encoding UTF8 -ErrorAction Stop
                if ($cacheContent) {
                    $cacheObj = $cacheContent | ConvertFrom-Json
                    foreach ($prop in $cacheObj.PSObject.Properties) {
                        $localCache[$prop.Name] = @{}
                        foreach ($subProp in $prop.Value.PSObject.Properties) {
                            $localCache[$prop.Name][$subProp.Name] = $subProp.Value
                        }
                    }
                }
            }
            catch {
                Write-ToLog "Warning: Could not read local deferral cache: $_" "Yellow"
            }
        }

        if ($localCache.ContainsKey($App.Id) -and $localCache[$App.Id].ContainsKey($App.AvailableVersion)) {
            $cachedEntry = $localCache[$App.Id][$App.AvailableVersion]
            if ($cachedEntry.ReleaseDateUtc) {
                try {
                    $releaseDateUtc = [DateTime]::Parse(
                        $cachedEntry.ReleaseDateUtc,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
                    )
                    Write-ToLog "$($App.Name) : Found in local cache." "Gray"
                }
                catch {
                    $releaseDateUtc = $null
                }
            }
        }
    }

    # Step 3c: Cache Miss on both Shared & Local -> Query GitHub API
    if (-not $releaseDateUtc) {
        $token = if ($Config -and $Config.WAU_GitHubToken) { $Config.WAU_GitHubToken } elseif ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $null }

        try {
            $relInfo = Get-WingetPackageReleaseDate -Id $App.Id -Version $App.AvailableVersion -Token $token -ErrorAction Stop
            if ($relInfo -and $relInfo.ReleaseDateUtc) {
                $releaseDateUtc = $relInfo.ReleaseDateUtc

                # 1. Update Shared Cache atomically (if available)
                if ($sharedCacheAvailable) {
                    $tmpSharedFile = Join-Path $SharedCachePath "$safeId#$safeVersion.tmp_$([Guid]::NewGuid().ToString('N'))"
                    $sharedPayload = [PSCustomObject]@{
                        Id               = $App.Id
                        Version          = $App.AvailableVersion
                        ReleaseDateUtc   = $releaseDateUtc.ToString("o")
                        ReleaseDateLocal = $releaseDateUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
                        Source           = $relInfo.Source
                        CreatedBy        = $env:COMPUTERNAME
                        CreatedAtUtc     = ([DateTime]::UtcNow).ToString("o")
                    } | ConvertTo-Json -Depth 3

                    try {
                        Set-Content -Path $tmpSharedFile -Value $sharedPayload -Encoding UTF8 -Force
                        Move-Item -Path $tmpSharedFile -Destination $sharedPkgFilePath -Force -ErrorAction Stop
                        Write-ToLog "$($App.Name) : Saved to shared cache." "Gray"
                    }
                    catch {
                        # Another client won the race or file locked - clean up tmp
                        Remove-Item -Path $tmpSharedFile -Force -ErrorAction SilentlyContinue
                        # Retry reading the winner's file
                        Start-Sleep -Milliseconds 300
                        if (Test-Path $sharedPkgFilePath) {
                            try {
                                $sharedJson = Get-Content -Path $sharedPkgFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
                                $releaseDateUtc = [DateTime]::Parse($sharedJson.ReleaseDateUtc, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
                            } catch {}
                        }
                    }
                }

                # 2. Update Local Cache
                if (-not $localCache.ContainsKey($App.Id)) {
                    $localCache[$App.Id] = @{}
                }
                $localCache[$App.Id][$App.AvailableVersion] = [PSCustomObject]@{
                    ReleaseDateUtc   = $releaseDateUtc.ToString("o")
                    ReleaseDateLocal = $releaseDateUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
                    Source           = $relInfo.Source
                    CachedAtUtc      = ([DateTime]::UtcNow).ToString("o")
                }

                try {
                    $localCache | ConvertTo-Json -Depth 5 | Set-Content -Path $localCacheFile -Encoding UTF8 -Force
                }
                catch {
                    Write-ToLog "Warning: Could not save local deferral cache: $_" "Yellow"
                }
            }
        }
        catch {
            Write-ToLog "Warning: Could not determine release date for '$($App.Name)' ($($App.Id)): $_. Proceeding with update." "Yellow"
            return $false
        }
    }

    if (-not $releaseDateUtc) {
        Write-ToLog "Warning: Release date for '$($App.Name)' ($($App.Id)) could not be resolved. Proceeding with update." "Yellow"
        return $false
    }

    # Step 4: Evaluate deferral threshold
    $nowUtc = [DateTime]::UtcNow
    $ageDays = ($nowUtc - $releaseDateUtc).TotalDays

    $modNotice = if ($isPerAppMod) { " [per-app mod]" } else { "" }

    if ($ageDays -lt $deferralDays) {
        $remainingDays = [Math]::Round($deferralDays - $ageDays, 1)
        $deferUntil = $releaseDateUtc.AddDays($deferralDays).ToLocalTime().ToString("yyyy-MM-dd HH:mm")
        $releaseStr = $releaseDateUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm")
        if ($App) {
            $App | Add-Member NoteProperty DeferUntil $deferUntil -Force
            $App | Add-Member NoteProperty ReleaseDate $releaseStr -Force
            $App | Add-Member NoteProperty DeferralDays $deferralDays -Force
            $App | Add-Member NoteProperty DeferralRemainingDays $remainingDays -Force
        }
        Write-ToLog "$($App.Name) : Upgrade to v$($App.AvailableVersion) is deferred ($remainingDays days remaining, until $deferUntil). Released on $releaseStr ($([Math]::Round($ageDays, 1)) days ago, policy: $deferralDays days$modNotice)." "DarkYellow"
        return $true
    }
    else {
        Write-ToLog "$($App.Name) : Deferral period passed ($([Math]::Round($ageDays, 1)) days >= $deferralDays days$modNotice). Ready to upgrade to v$($App.AvailableVersion)." "Green"
        return $false
    }
}
