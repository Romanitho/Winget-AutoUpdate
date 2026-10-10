# Download into the destination directory, checking every redirect before following it.
# Only replace an existing file after the complete HTTPS response has been received.
function Save-WauHttpsFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$Destination,
        [switch]$OnlyIfNewer
    )

    $current = $null
    if (-not [Uri]::TryCreate($Uri, [UriKind]::Absolute, [ref]$current) -or
        $current.Scheme -ne [Uri]::UriSchemeHttps) {
        throw 'HTTPS URL required.'
    }
    $directory = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Download destination directory does not exist: $directory"
    }

    $temporary = Join-Path $directory ('.wau-' + [guid]::NewGuid().ToString('N') + '.download')
    $backup = Join-Path $directory ('.wau-' + [guid]::NewGuid().ToString('N') + '.backup')
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        for ($hop = 0; $hop -le 5; $hop++) {
            if ($current.Scheme -ne [Uri]::UriSchemeHttps) {
                throw 'HTTPS downgrade redirect rejected.'
            }
            $request = [Net.HttpWebRequest]::Create($current)
            $request.AllowAutoRedirect = $false
            $request.Method = 'GET'
            $request.Timeout = 300000
            $request.ReadWriteTimeout = 300000
            $response = $null
            try {
                try { $response = [Net.HttpWebResponse]$request.GetResponse() }
                catch [Net.WebException] {
                    if ($_.Exception.Response -is [Net.HttpWebResponse]) {
                        $response = [Net.HttpWebResponse]$_.Exception.Response
                    }
                    else { throw }
                }
                $status = [int]$response.StatusCode
                if ($status -ge 300 -and $status -lt 400) {
                    if ($hop -eq 5) { throw 'Too many HTTPS redirects.' }
                    $location = $response.Headers['Location']
                    if ([string]::IsNullOrWhiteSpace($location)) { throw 'Redirect has no Location header.' }
                    $current = [Uri]::new($current, $location)
                    continue
                }
                if ($status -lt 200 -or $status -ge 300) {
                    throw "HTTPS download failed with HTTP $status."
                }

                $lastModified = [datetime]::MinValue
                $hasLastModified = [datetime]::TryParse([string]$response.Headers['Last-Modified'],
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$lastModified)
                $inputStream = $response.GetResponseStream()
                $outputStream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $inputStream.CopyTo($outputStream) }
                finally { $outputStream.Dispose(); $inputStream.Dispose() }

                if ($OnlyIfNewer -and $hasLastModified -and
                    (Test-Path -LiteralPath $Destination -PathType Leaf) -and
                    $lastModified.ToUniversalTime() -le [IO.File]::GetLastWriteTimeUtc($Destination)) {
                    return [pscustomobject]@{ Changed=$false; HasLastModified=$true; FinalUri=$current.AbsoluteUri }
                }
                if (Test-Path -LiteralPath $Destination -PathType Leaf) {
                    [IO.File]::Replace($temporary, $Destination, $backup)
                }
                else {
                    [IO.File]::Move($temporary, $Destination)
                }
                if ($hasLastModified) {
                    [IO.File]::SetLastWriteTimeUtc($Destination, $lastModified.ToUniversalTime())
                }
                return [pscustomobject]@{
                    Changed=$true; HasLastModified=[bool]$hasLastModified; FinalUri=$current.AbsoluteUri
                }
            }
            finally { if ($response) { $response.Close() } }
        }
        throw 'Too many HTTPS redirects.'
    }
    finally {
        Remove-Item -LiteralPath $temporary,$backup -Force -ErrorAction SilentlyContinue
    }
}