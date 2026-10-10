<#
.SYNOPSIS
    Gets the precise merge/release date of a specified Winget package version from GitHub.

.DESCRIPTION
    Retrieves the precise merge/release date of a Winget package version from GitHub.
    Tries the public GitHub commit Atom feed first (which avoids REST API rate limits and
    does not require a GitHub Token). If the Atom feed fails or returns no entries,
    gracefully falls back to the GitHub REST API.

    Atom Feed Logic:
     1. Construct Atom feed URL for the package (or specific version folder).
     2. Parse latest/oldest commit timestamp, commit SHA, PR number and version from Atom XML.
     3. Return release details with Source = "AtomFeed".

    REST API Fallback Logic:
     1. If a Version is specified, target that specific version folder. Otherwise, list
        version subfolders (GitHub Contents API) and determine the highest version using
        Compare-WingetVersion.
     2. Query the commits that touched that specific version folder.
     3. Within that version folder's commit history, take the OLDEST commit (the one that
        originally introduced the version).
     4. Look up the pull request that introduced that commit (GET /commits/{sha}/pulls)
        and use its `merged_at` timestamp.
     5. If no associated PR is found, fall back to the commit's committer date.

.PARAMETER Id
    The Winget Package Identifier (e.g., Google.Chrome).

.PARAMETER Version
    Optional specific version string to query. If omitted, the latest version is detected.

.PARAMETER Token
    Optional GitHub Personal Access Token to raise the API rate limit from 60 to
    5000 requests/hour for the REST API fallback. Can also be supplied via $env:GITHUB_TOKEN.

.OUTPUTS
    PSCustomObject with Id, LatestVersion, ReleaseDateUtc, ReleaseDateLocal, Source,
    PullRequest, PullRequestUrl, CommitSha, CommitUrl.

.EXAMPLE
    Get-WingetPackageReleaseDate -Id 7zip.7zip

.EXAMPLE
    Get-WingetPackageReleaseDate -Id Google.Chrome -Version "120.0.6099.130"
#>
function Get-WingetPackageReleaseDate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Id,

        [Parameter(Mandatory = $false)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [string]$Token = $env:GITHUB_TOKEN
    )

    begin {
        # Ensure TLS 1.2 is enabled for PowerShell 5.1 compatibility
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        } catch {
            # Ignore if runtime doesn't allow setting SecurityProtocol
        }

        $headers = @{
            "User-Agent" = "PowerShell-Winget-ReleaseDate-Query"
            "Accept"     = "application/vnd.github+json"
        }
        if (-not [string]::IsNullOrWhiteSpace($Token)) {
            $headers["Authorization"] = "Bearer $($Token.Trim())"
        }
    }

    process {
        $Id = $Id.Trim()

        if ([string]::IsNullOrWhiteSpace($Id)) {
            Write-Error "The provided ID is empty."
            return
        }

        Write-Verbose "Resolving release date for '$Id'."

        $firstChar = $Id.Substring(0, 1).ToLower()
        $path      = $Id.Replace('.', '/')

        # =====================================================================
        # Step 1: Try GitHub Atom feed first (No REST API rate limit)
        # =====================================================================
        try {
            $atomResult = $null

            if (-not [string]::IsNullOrWhiteSpace($Version)) {
                $targetVer = $Version.Trim()
                # Try version-specific feed first
                $verFeedUrl = "https://github.com/microsoft/winget-pkgs/commits/master/manifests/$firstChar/$path/$([uri]::EscapeDataString($targetVer)).atom"
                try {
                    $entries = @(Invoke-RestMethod -Uri $verFeedUrl -ErrorAction Stop)
                    if ($entries.Count -gt 0) {
                        # Look for commits matching this version; the oldest commit in the version feed introduced it
                        $matched = @($entries | Where-Object { $_.title -match [regex]::Escape($targetVer) })
                        $selected = if ($matched.Count -gt 0) { $matched[$matched.Count - 1] } else { $entries[$entries.Count - 1] }

                        $commitUrl = $selected.link.href
                        $sha       = if ($selected.id -match 'Commit/([a-f0-9]{40})') { $Matches[1] } else { $commitUrl.Split('/')[-1] }
                        $prNumber  = if ($selected.title -match '#(\d+)') { [int]$Matches[1] } else { $null }
                        $prUrl     = if ($prNumber) { "https://github.com/microsoft/winget-pkgs/pull/$prNumber" } else { $null }
                        $ver       = if ($selected.title -match 'version\s+([^\s\(\)#]+)') { $Matches[1] } else { $targetVer }
                        $relDateUtc = [datetime]::Parse(
                            $selected.updated,
                            [System.Globalization.CultureInfo]::InvariantCulture,
                            [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
                        )

                        $atomResult = [PSCustomObject]@{
                            Id               = $Id
                            LatestVersion    = $ver
                            ReleaseDateUtc   = $relDateUtc
                            ReleaseDateLocal = $relDateUtc.ToLocalTime()
                            Source           = "AtomFeed"
                            PullRequest      = $prNumber
                            PullRequestUrl   = $prUrl
                            CommitSha        = $sha
                            CommitUrl        = $commitUrl
                        }
                    }
                } catch {
                    Write-Verbose "Version-specific atom feed for '$Id' ($targetVer) failed: $_"
                }

                # If version-specific feed didn't find it, try package-level feed
                if (-not $atomResult) {
                    $pkgFeedUrl = "https://github.com/microsoft/winget-pkgs/commits/master/manifests/$firstChar/$path.atom"
                    $entries = @(Invoke-RestMethod -Uri $pkgFeedUrl -ErrorAction Stop)
                    $matched = @($entries | Where-Object { $_.title -match [regex]::Escape($targetVer) })
                    if ($matched.Count -gt 0) {
                        $selected = $matched[$matched.Count - 1]
                        $commitUrl = $selected.link.href
                        $sha       = if ($selected.id -match 'Commit/([a-f0-9]{40})') { $Matches[1] } else { $commitUrl.Split('/')[-1] }
                        $prNumber  = if ($selected.title -match '#(\d+)') { [int]$Matches[1] } else { $null }
                        $prUrl     = if ($prNumber) { "https://github.com/microsoft/winget-pkgs/pull/$prNumber" } else { $null }
                        $ver       = if ($selected.title -match 'version\s+([^\s\(\)#]+)') { $Matches[1] } else { $targetVer }
                        $relDateUtc = [datetime]::Parse(
                            $selected.updated,
                            [System.Globalization.CultureInfo]::InvariantCulture,
                            [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
                        )

                        $atomResult = [PSCustomObject]@{
                            Id               = $Id
                            LatestVersion    = $ver
                            ReleaseDateUtc   = $relDateUtc
                            ReleaseDateLocal = $relDateUtc.ToLocalTime()
                            Source           = "AtomFeed"
                            PullRequest      = $prNumber
                            PullRequestUrl   = $prUrl
                            CommitSha        = $sha
                            CommitUrl        = $commitUrl
                        }
                    }
                }
            } else {
                # No specific version requested: take latest entry from package-level feed
                $pkgFeedUrl = "https://github.com/microsoft/winget-pkgs/commits/master/manifests/$firstChar/$path.atom"
                $entries = @(Invoke-RestMethod -Uri $pkgFeedUrl -ErrorAction Stop)
                if ($entries.Count -gt 0) {
                    $latest    = $entries[0]
                    $commitUrl = $latest.link.href
                    $sha       = if ($latest.id -match 'Commit/([a-f0-9]{40})') { $Matches[1] } else { $commitUrl.Split('/')[-1] }
                    $prNumber  = if ($latest.title -match '#(\d+)') { [int]$Matches[1] } else { $null }
                    $prUrl     = if ($prNumber) { "https://github.com/microsoft/winget-pkgs/pull/$prNumber" } else { $null }
                    $ver       = if ($latest.title -match 'version\s+([^\s\(\)#]+)') { $Matches[1] } else { $null }
                    $relDateUtc = [datetime]::Parse(
                        $latest.updated,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
                    )

                    $atomResult = [PSCustomObject]@{
                        Id               = $Id
                        LatestVersion    = $ver
                        ReleaseDateUtc   = $relDateUtc
                        ReleaseDateLocal = $relDateUtc.ToLocalTime()
                        Source           = "AtomFeed"
                        PullRequest      = $prNumber
                        PullRequestUrl   = $prUrl
                        CommitSha        = $sha
                        CommitUrl        = $commitUrl
                    }
                }
            }

            if ($atomResult) {
                Write-Verbose "Successfully resolved release details for '$Id' via Atom feed."
                return $atomResult
            }
        } catch {
            Write-Verbose "Atom feed retrieval failed for '$Id', falling back to GitHub REST API: $_"
        }

        # =====================================================================
        # Step 2: Fallback to GitHub REST API
        # =====================================================================
        Write-Verbose "Querying GitHub REST API for '$Id'..."

        try {
            $segments  = $Id.Split('.') | ForEach-Object { [uri]::EscapeDataString($_) }
            $repoPath  = "manifests/$firstChar/$($segments -join '/')"

            $targetVersion = $null
            $versionCommits = $null

            # Fast path: If a specific version was requested, try querying its commits directly
            if (-not [string]::IsNullOrWhiteSpace($Version)) {
                $targetVersion = $Version.Trim()
                $versionPath = "$repoPath/$([uri]::EscapeDataString($targetVersion))"
                $versionCommitsUri = "https://api.github.com/repos/microsoft/winget-pkgs/commits?path=$versionPath&per_page=100"
                try {
                    $versionCommits = Invoke-RestMethod -Uri $versionCommitsUri -Headers $headers -ErrorAction Stop
                } catch {
                    Write-Verbose "Direct commit query for '$Id' version '$targetVersion' failed, falling back to folder listing: $_"
                    $versionCommits = $null
                    $targetVersion = $null
                }
            }

            # Step 1: list version subfolders and determine version if not resolved yet
            if (-not $targetVersion -or -not $versionCommits) {
                $contentsUri = "https://api.github.com/repos/microsoft/winget-pkgs/contents/$repoPath"
                $contents = Invoke-RestMethod -Uri $contentsUri -Headers $headers -ErrorAction Stop

                $versionFolders = $contents | Where-Object { $_.type -eq 'dir' }
                if (-not $versionFolders -or $versionFolders.Count -eq 0) {
                    Write-Error "No version folders found for '$Id'. Please check the exact ID."
                    return
                }

                # If specific version was requested, look for exact match in folder list
                if (-not [string]::IsNullOrWhiteSpace($Version)) {
                    $matchedFolder = $versionFolders | Where-Object { $_.name -eq $Version.Trim() } | Select-Object -First 1
                    if ($matchedFolder) {
                        $targetVersion = $matchedFolder.name
                    }
                }

                # Otherwise (or if not matched), pick highest version using Compare-WingetVersion
                if (-not $targetVersion) {
                    $targetVersion = $versionFolders[0].name
                    foreach ($vf in $versionFolders) {
                        if ((Compare-WingetVersion -A $vf.name -B $targetVersion) -gt 0) {
                            $targetVersion = $vf.name
                        }
                    }
                }
                Write-Verbose "Target version detected for '$Id': $targetVersion"

                # Step 2: get commits that touched this specific version folder
                $versionPath = "$repoPath/$([uri]::EscapeDataString($targetVersion))"
                $versionCommitsUri = "https://api.github.com/repos/microsoft/winget-pkgs/commits?path=$versionPath&per_page=100"
                $versionCommits = Invoke-RestMethod -Uri $versionCommitsUri -Headers $headers -ErrorAction Stop
            }

            if (-not $versionCommits -or $versionCommits.Count -eq 0) {
                Write-Error "No commit history found for version '$targetVersion' of '$Id'."
                return
            }

            # Step 3: the OLDEST commit in the list is the one that introduced the version
            # (GitHub returns commits newest-first, so it's the last element)
            $introducingCommit = $versionCommits[$versionCommits.Count - 1]
            $sha       = $introducingCommit.sha
            $commitUrl = $introducingCommit.html_url

            # Step 4: resolve the exact merge timestamp via the associated pull request
            $pullsUri = "https://api.github.com/repos/microsoft/winget-pkgs/commits/$sha/pulls"
            $prNumber = $null
            $prUrl    = $null
            $releaseDate = $null
            $source = "CommitDate"

            try {
                $pulls = Invoke-RestMethod -Uri $pullsUri -Headers $headers -ErrorAction Stop
                $mergedPr = $pulls | Where-Object { $_.merged_at } | Sort-Object { [datetime]$_.merged_at } -Descending | Select-Object -First 1

                if ($mergedPr) {
                    $releaseDate = [datetime]::Parse(
                        $mergedPr.merged_at,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
                    )
                    $prNumber = $mergedPr.number
                    $prUrl    = $mergedPr.html_url
                    $source   = "PullRequestMergedAt"
                }
            } catch {
                Write-Verbose "Could not resolve associated pull request for '$Id' (sha $sha): $_"
            }

            # Step 5: fallback to the commit's own committer date if no PR could be resolved
            if (-not $releaseDate) {
                $releaseDate = [datetime]::Parse(
                    $introducingCommit.commit.committer.date,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
                )
            }

            [PSCustomObject]@{
                Id               = $Id
                LatestVersion    = $targetVersion
                ReleaseDateUtc   = $releaseDate
                ReleaseDateLocal = $releaseDate.ToLocalTime()
                Source           = $source
                PullRequest      = $prNumber
                PullRequestUrl   = $prUrl
                CommitSha        = $sha
                CommitUrl        = $commitUrl
            }
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
            }
            switch ($statusCode) {
                404 { Write-Error "Package '$Id' not found in winget-pkgs (404). Check the exact ID/case." }
                403 { Write-Error "GitHub API rate limit exceeded (403) while querying '$Id'. Supply -Token to raise the limit." }
                default { Write-Error "GitHub API query failed for '$Id': $_" }
            }
        }
    }
}
