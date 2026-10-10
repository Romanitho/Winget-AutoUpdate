# Scope is installation identity, not a guess based on a directory or package ID.
function Get-WauAppKey ($App) {
    $identity = '{0}|{1}|{2}|{3}' -f $App.Source, $App.Id, $App.Scope, $App.UserSid
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity.ToLowerInvariant())))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Get-WauDeadlineRegistryPath {
    param($App, [string]$DeadlineRegPath = 'HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\UpdateDeadlines')
    $packageId = if ($App.Id) { [string]$App.Id } else { [string]$App.PackageId }
    if (-not $packageId -or $packageId -notmatch '^[A-Za-z0-9][A-Za-z0-9._+\-]{0,255}$') {
        throw 'Invalid WinGet package ID for deadline registry path.'
    }
    $source = if ($App.Source) { [string]$App.Source } else { 'winget' }
    if ($source -notmatch '^[A-Za-z0-9][A-Za-z0-9._+ \-]{0,127}$') {
        throw 'Invalid WinGet source for deadline registry path.'
    }
    if ($App.Scope -notin @('user','machine')) { throw 'Invalid deadline scope.' }
    $path = Join-Path (Join-Path $DeadlineRegPath $packageId) $source
    if ($App.Scope -eq 'machine') { return Join-Path $path 'machine' }
    $sid = [string]$App.UserSid
    if ($sid -notmatch '^S-1-(?:5-21|12-1)-\d+-\d+-\d+-\d+$') { throw 'Invalid deadline user SID.' }
    return Join-Path (Join-Path $path 'user') $sid
}

function Remove-WauUpdateDeadline {
    param($App, [string]$DeadlineRegPath = 'HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\UpdateDeadlines')
    $leaf = Get-WauDeadlineRegistryPath -App $App -DeadlineRegPath $DeadlineRegPath
    Remove-Item -LiteralPath $leaf -Recurse -Force -ErrorAction SilentlyContinue
    # Remove empty SID/scope, source and package containers, but never the root.
    $parent = Split-Path $leaf -Parent
    while ($parent -and $parent -ne $DeadlineRegPath -and $parent.StartsWith($DeadlineRegPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $children = @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue)
        $container = Get-ItemProperty -LiteralPath $parent -ErrorAction SilentlyContinue
        $dataProperties = @($container.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$' })
        if ($children.Count -or $dataProperties.Count) { break }
        Remove-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
        $parent = Split-Path $parent -Parent
    }
}


function Remove-WauLegacyDeadlineEntry {
    param($Entry)
    if (@(Get-ChildItem -LiteralPath $Entry.PSPath -ErrorAction SilentlyContinue).Count) {
        # A legacy ID key may now contain the new scope children. Keep those and
        # remove only the obsolete values stored directly on the package key.
        $properties = Get-ItemProperty -LiteralPath $Entry.PSPath -ErrorAction SilentlyContinue
        foreach ($property in @($properties.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$' })) {
            Remove-ItemProperty -LiteralPath $Entry.PSPath -Name $property.Name -ErrorAction SilentlyContinue
        }
    }
    else {
        Remove-Item -LiteralPath $Entry.PSPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Set-WauDeadlineLeafValues {
    param([string]$Path, $App, [datetime]$FirstDetected, [datetime]$Deadline, [string]$AvailableVersion)
    New-Item -Path $Path -Force | Out-Null
    Set-ItemProperty -LiteralPath $Path -Name FirstDetected -Value $FirstDetected.ToString('yyyy-MM-dd HH:mm:ss')
    Set-ItemProperty -LiteralPath $Path -Name Deadline -Value $Deadline.ToString('yyyy-MM-dd HH:mm:ss')
    Set-ItemProperty -LiteralPath $Path -Name AvailableVersion -Value $AvailableVersion
    Set-ItemProperty -LiteralPath $Path -Name PackageId -Value ([string]$App.Id)
    Set-ItemProperty -LiteralPath $Path -Name Source -Value $(if ($App.Source) { [string]$App.Source } else { 'winget' })
    Set-ItemProperty -LiteralPath $Path -Name Scope -Value ([string]$App.Scope)
    Set-ItemProperty -LiteralPath $Path -Name UserSid -Value ([string]$App.UserSid)
    Set-ItemProperty -LiteralPath $Path -Name IdentityKey -Value (Get-WauAppKey $App)
}

# Move the current ID\machine and ID\user\SID layout below the recorded
# WinGet source. Copy and verify first; never restart the existing deadline.
function Move-WauDeadlineScopeChildren {
    param([string]$DeadlineRegPath)
    foreach ($packageKey in @(Get-ChildItem -LiteralPath $DeadlineRegPath -ErrorAction SilentlyContinue)) {
        if ($packageKey.PSChildName -notmatch '^[A-Za-z0-9][A-Za-z0-9._+\-]{0,255}$') { continue }
        $legacyLeaves = @()
        $machinePath = Join-Path $packageKey.PSPath 'machine'
        $userPath = Join-Path $packageKey.PSPath 'user'
        if (Test-Path -LiteralPath $machinePath) {
            $legacyLeaves += Get-Item -LiteralPath $machinePath
        }
        if (Test-Path -LiteralPath $userPath) {
            $legacyLeaves += @(Get-ChildItem -LiteralPath $userPath -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match '^S-1-(?:5-21|12-1)-\d+-\d+-\d+-\d+$' })
        }
        foreach ($leaf in $legacyLeaves) {
            $props = Get-ItemProperty -LiteralPath $leaf.PSPath -ErrorAction SilentlyContinue
            if (-not $props.FirstDetected -or -not $props.Deadline) { continue }
            $scope = if ($leaf.PSChildName -eq 'machine') { 'machine' } else { 'user' }
            $sid = if ($scope -eq 'user') { [string]$leaf.PSChildName } else { '' }
            $app = [pscustomobject]@{
                Id= $(if ($props.PackageId) { [string]$props.PackageId } else { [string]$packageKey.PSChildName })
                Source= $(if ($props.Source) { [string]$props.Source } else { 'winget' })
                Scope=$scope; UserSid=$sid
            }
            try {
                $first = [datetime]::MinValue
                $due = [datetime]::MinValue
                if (-not [datetime]::TryParse([string]$props.FirstDetected, [ref]$first) -or
                    -not [datetime]::TryParse([string]$props.Deadline, [ref]$due)) {
                    throw 'Invalid deadline date.'
                }
                $destination = Get-WauDeadlineRegistryPath -App $app -DeadlineRegPath $DeadlineRegPath
                $existing = Get-ItemProperty -LiteralPath $destination -ErrorAction SilentlyContinue
                if ($existing) {
                    $existingFirst = [datetime]::MaxValue
                    $existingDue = [datetime]::MaxValue
                    if ([datetime]::TryParse([string]$existing.FirstDetected, [ref]$existingFirst) -and $existingFirst -lt $first) {
                        $first = $existingFirst
                    }
                    if ([datetime]::TryParse([string]$existing.Deadline, [ref]$existingDue) -and $existingDue -lt $due) {
                        $due = $existingDue
                    }
                }
                $version = if ($props.AvailableVersion) { [string]$props.AvailableVersion } else { '' }
                Set-WauDeadlineLeafValues -Path $destination -App $app -FirstDetected $first -Deadline $due -AvailableVersion $version
                $check = Get-ItemProperty -LiteralPath $destination -ErrorAction Stop
                if ($check.IdentityKey -ne (Get-WauAppKey $app) -or
                    $check.FirstDetected -ne $first.ToString('yyyy-MM-dd HH:mm:ss') -or
                    $check.Deadline -ne $due.ToString('yyyy-MM-dd HH:mm:ss')) {
                    throw 'Source-level deadline verification failed.'
                }
                Remove-Item -LiteralPath $leaf.PSPath -Recurse -Force -ErrorAction Stop
                Write-ToLog "Deadline registry source migrated: $($app.Id) / $($app.Source) / $scope"
            }
            catch {
                Write-ToLog "Deadline source migration failed for $($app.Id): $_" 'Yellow'
            }
        }
        if ((Test-Path -LiteralPath $userPath) -and
            -not @(Get-ChildItem -LiteralPath $userPath -ErrorAction SilentlyContinue).Count) {
            Remove-Item -LiteralPath $userPath -Force -ErrorAction SilentlyContinue
        }
    }
}
function Convert-WauDeadlineRegistryLayout {
    param([array]$Apps, [string]$DeadlineRegPath = 'HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\UpdateDeadlines')
    if (-not (Test-Path -LiteralPath $DeadlineRegPath)) { return }
    Move-WauDeadlineScopeChildren -DeadlineRegPath $DeadlineRegPath

    # Snapshot direct children only. New package/scope leaves created during this
    # pass must never be considered legacy input in the same run.
    foreach ($entry in @(Get-ChildItem -LiteralPath $DeadlineRegPath -ErrorAction SilentlyContinue)) {
        $props = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
        if (-not $props.FirstDetected -or -not $props.Deadline) { continue }

        $packageId = if ($props.PackageId) { [string]$props.PackageId } else { [string]$entry.PSChildName }
        $matches = @($Apps | Where-Object {
            $_.Id -eq $packageId -and
            (-not $props.Scope -or $_.Scope -eq $props.Scope) -and
            (-not $props.UserSid -or $_.UserSid -eq $props.UserSid) -and
            (-not $props.Source -or $_.Source -eq $props.Source)
        })
        if (-not $matches.Count) {
            Remove-WauLegacyDeadlineEntry -Entry $entry
            Write-ToLog "Deadline purged during registry migration (app no longer outdated): $packageId"
            continue
        }

        $first = [datetime]::MinValue
        $due = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$props.FirstDetected, [ref]$first) -or
            -not [datetime]::TryParse([string]$props.Deadline, [ref]$due)) {
            Remove-WauLegacyDeadlineEntry -Entry $entry
            Write-ToLog "Deadline purged during registry migration (invalid dates): $packageId" 'Yellow'
            continue
        }

        $migrated = $true
        foreach ($app in $matches) {
            try {
                $destination = Get-WauDeadlineRegistryPath -App $app -DeadlineRegPath $DeadlineRegPath
                $existing = Get-ItemProperty -LiteralPath $destination -ErrorAction SilentlyContinue
                $mergedFirst = $first
                $mergedDue = $due
                if ($existing) {
                    $existingFirst = [datetime]::MaxValue
                    $existingDue = [datetime]::MaxValue
                    if ([datetime]::TryParse([string]$existing.FirstDetected, [ref]$existingFirst) -and $existingFirst -lt $mergedFirst) {
                        $mergedFirst = $existingFirst
                    }
                    if ([datetime]::TryParse([string]$existing.Deadline, [ref]$existingDue) -and $existingDue -lt $mergedDue) {
                        $mergedDue = $existingDue
                    }
                }
                $version = if ($props.AvailableVersion) { [string]$props.AvailableVersion } else { [string]$app.AvailableVersion }
                Set-WauDeadlineLeafValues -Path $destination -App $app -FirstDetected $mergedFirst -Deadline $mergedDue -AvailableVersion $version

                $check = Get-ItemProperty -LiteralPath $destination -ErrorAction Stop
                if ($check.IdentityKey -ne (Get-WauAppKey $app) -or $check.PackageId -ne $app.Id -or $check.Scope -ne $app.Scope) {
                    throw 'Migrated deadline verification failed.'
                }
            }
            catch {
                $migrated = $false
                Write-ToLog "Deadline migration failed for $packageId`: $_" 'Yellow'
                break
            }
        }
        if (-not $migrated) { continue }

        # Delete legacy input only after every matching scope/user leaf was
        # written and verified successfully.
        Remove-WauLegacyDeadlineEntry -Entry $entry
        Write-ToLog "Deadline registry entry migrated: $packageId"
    }
}
function Get-WauCleanAppName ($Name, $Version) {
    $clean = [string]$Name
    if ($Version) {
        $escapedVer = [regex]::Escape($Version)
        $clean = $clean -replace "(?i)\s*(version\s*|v\.?\s*)?$escapedVer\b", ""
        $verParts = $Version.Split('.')
        if ($verParts.Count -ge 3) {
            $threePart = [regex]::Escape("$($verParts[0]).$($verParts[1]).$($verParts[2])")
            $clean = $clean -replace "(?i)\s*(version\s*|v\.?\s*)?$threePart\b", ""
        }
        if ($verParts.Count -ge 2) {
            $twoPart = [regex]::Escape("$($verParts[0]).$($verParts[1])")
            $clean = $clean -replace "(?i)\s*(version\s*|v\.?\s*)?$twoPart\b", ""
        }
    }
    return $clean.Trim()
}

function Test-WauSameVersion ([string]$Installed, [string]$Expected) {
    if ([string]::IsNullOrWhiteSpace($Installed) -or [string]::IsNullOrWhiteSpace($Expected)) { return $false }
    $inst = $Installed.Trim().TrimStart('v', 'V')
    $exp  = $Expected.Trim().TrimStart('v', 'V')
    if ($inst -eq $exp) { return $true }

    # Normalize dot-separated numeric versions: strip trailing zero segments and compare integer parts
    if ($inst -match '^\d+(\.\d+)+$' -and $exp -match '^\d+(\.\d+)+$') {
        try {
            $instParts = [System.Collections.Generic.List[long]]::new([long[]]($inst.Split('.') | ForEach-Object { [long]$_ }))
            $expParts  = [System.Collections.Generic.List[long]]::new([long[]]($exp.Split('.') | ForEach-Object { [long]$_ }))
            while ($instParts.Count -gt 0 -and $instParts[$instParts.Count - 1] -eq 0) {
                $instParts.RemoveAt($instParts.Count - 1)
            }
            while ($expParts.Count -gt 0 -and $expParts[$expParts.Count - 1] -eq 0) {
                $expParts.RemoveAt($expParts.Count - 1)
            }
            if ($instParts.Count -ne $expParts.Count) { return $false }
            for ($i = 0; $i -lt $instParts.Count; $i++) {
                if ($instParts[$i] -ne $expParts[$i]) { return $false }
            }
            return $true
        } catch {}
    }

    # WinGet manifests and ARP often differ only by trailing zero components (e.g. 26.03.00.0 vs 26.03).
    $instClean = $inst -replace '(\.0+)+$', ''
    $expClean  = $exp -replace '(\.0+)+$', ''
    return ($instClean -eq $expClean)
}

function Invoke-WauWinget {
    param([string[]]$Arguments)
    $output = @(& $Script:Winget @Arguments 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

function Invoke-WauWingetTimed {
    param([string[]]$Arguments, [int]$TimeoutSeconds = 30)
    if ($Script:Winget -isnot [string] -or [string]::IsNullOrWhiteSpace($Script:Winget)) {
        return Invoke-WauWinget -Arguments $Arguments
    }
    $quoted = foreach ($argument in $Arguments) {
        if ($argument -notmatch '[\s"]') { $argument; continue }
        # Windows CommandLineToArgvW escaping: double backslashes before quotes
        # and at the end of a quoted argument.
        '"' + ([regex]::Replace($argument, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
    }
    $stdoutPath = Join-Path $env:TEMP ('wau-winget-' + [guid]::NewGuid().ToString('N') + '.out')
    $stderrPath = Join-Path $env:TEMP ('wau-winget-' + [guid]::NewGuid().ToString('N') + '.err')
    $process = $null
    try {
        $process = Start-Process -FilePath $Script:Winget -ArgumentList ($quoted -join ' ') -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            return [pscustomobject]@{ExitCode=1460;Output='WinGet metadata query timed out.'}
        }
        $output = @(
            Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
            Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        ) -join "`n"
        return [pscustomobject]@{ExitCode=$process.ExitCode;Output=$output}
    }
    finally {
        if ($process) { $process.Dispose() }
        Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-WauWingetDetails {
    if ($null -eq $Script:WauHasListDetails) {
        $help = Invoke-WauWinget -Arguments @('list', '--help')
        $Script:WauHasListDetails = $help.ExitCode -eq 0 -and $help.Output.Contains('--details')
    }
    return $Script:WauHasListDetails
}

# New WinGet releases expose untruncated identities with list --details. The
# position of the installed version and the source [version] line are independent
# of UI language. Prefer this over terminal-column parsing whenever available.
function ConvertFrom-WauWingetDetails {
    param([string]$Text, [string]$Source, [switch]$Upgrade)
    $clean = $Text -replace '\x1b\[[0-9;?]*[A-Za-z]', ''
    $blocks = [regex]::Matches($clean, '(?ms)^(?:\(\d+/\d+\) )?(?<name>[^\s\r\n][^\r\n]*) \[(?<id>[^\]\r\n]+)\]\r?\n[^:\r\n]+:[ \t]*(?<version>[^\r\n]+)\r?\n(?<body>.*?)(?=^(?:\(\d+/\d+\) )?[^\s\r\n][^\r\n]* \[[^\]\r\n]+\]\r?\n|\z)')
    foreach ($block in $blocks) {
        $id = $block.Groups['id'].Value
        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+\-]*$') { continue }
        $available = [regex]::Match($block.Groups['body'].Value, ('(?m)^\s+' + [regex]::Escape($Source) + ' \[(?<version>[^\]\r\n]+)\]'))
        if ($Upgrade -and -not $available.Success) { continue }
        [pscustomobject]@{Name=$block.Groups['name'].Value;Id=$id;Version=$block.Groups['version'].Value.Trim()
            AvailableVersion=$available.Groups['version'].Value.Trim()}
    }
    if ($clean -match '(?m)^\S[^\r\n]* \[[^\]\r\n]+\]$' -and -not $blocks.Count) { throw 'Unrecognised WinGet detailed inventory format.' }
}

# WinGet renders tables in terminal cells, not UTF-16 offsets. Pad wide characters
# before slicing, and reject truncated identities instead of executing a wrong ID.
function ConvertFrom-WauWingetTable {
    param([string]$Text, [switch]$Upgrade)
    $lines = ($Text -replace '\x1b\[[0-9;?]*[A-Za-z]', '') -split '\r?\n'
    $starts = $null
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*-{5,}\s*$') {
            $starts = @([regex]::Matches($lines[$i-1], '\S+(?: \S+)*?(?=\s{2,}|$)') | ForEach-Object { $_.Index })
            continue
        }
        if (-not $starts -or $starts.Count -lt 3) { continue }
        $line = $lines[$i] -replace '([\u1100-\u115f\u2e80-\ua4cf\uac00-\ud7a3\uf900-\ufaff\ufe10-\ufe6f\uff01-\uff60])', ('$1' + [char]0x200B)
        if ($line.Length -le $starts[2]) { continue }
        $cells = @()
        for ($c = 0; $c -lt $starts.Count; $c++) {
            $end = if ($c + 1 -lt $starts.Count) { [math]::Min($starts[$c+1], $line.Length) } else { $line.Length }
            if ($end -le $starts[$c]) { $cells += ''; continue }
            $cells += $line.Substring($starts[$c], $end-$starts[$c]).Replace([string][char]0x200B, '').Trim()
        }
        if ($cells[1] -notmatch '^[A-Za-z0-9][A-Za-z0-9._+\-]*$' -or -not $cells[2]) { continue }
        if ($Upgrade -and ($cells.Count -lt 4 -or -not $cells[3])) { continue }
        [pscustomobject]@{
            Name = $cells[0]; Id = $cells[1]; Version = $cells[2]
            AvailableVersion = if ($Upgrade) { $cells[3] } else { '' }
        }
    }
}

function Get-WauInstallerSupport {
    param($App, [ValidateSet('user','machine')][string]$Scope, [string]$Source)
    $result = Invoke-WauWinget -Arguments @('show', '--id', $App.Id, '--exact', '--version', $App.AvailableVersion,
        '--source', $Source, '--scope', $Scope, '--accept-source-agreements', '--disable-interactivity')
    if ($result.ExitCode -ne 0) { return 'Unknown' }
    # A selected non-Store installer has a required SHA256. show can return 0 even
    # when no applicable installer exists; its exit code alone is not sufficient.
    if ($result.Output -match '(?im)^\s+[^\r\n:]*SHA256\s*:\s*[0-9a-f]{64}\s*$') { return 'Supported' }
    # show ends with an installer section. With no applicable installer it contains
    # one indented warning instead of key:value fields (ShowFlow.cpp). Recognise
    # the structure rather than an English/German translation. Store product IDs
    # contain a colon and deliberately remain Unknown here, never machine-only.
    $lines = @($result.Output -split '\r?\n')
    $lastHeader = -1
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match '^\S[^:]*:\s*$') { $lastHeader = $i; break }
    }
    if ($lastHeader -ge 0) {
        $detail = @($lines[($lastHeader + 1)..($lines.Count - 1)] | Where-Object { $_.Trim() })
        if ($detail.Count -eq 1 -and $detail[0] -notmatch ':' -and $result.Output.Contains("[$($App.Id)]")) { return 'Unavailable' }
    }
    return 'Unknown'
}

function Set-WauScopePlan {
    param($App, [string]$Source)
    # Inventory must stay fast: installer applicability is checked only for
    # selected user updates, immediately before consent/dispatch.
    $support = if ($App.Scope -eq 'user' -and $App.UserInstallerSupport) { $App.UserInstallerSupport }
               elseif ($App.Scope -eq 'machine' -and $App.MachineInstallerSupport) { $App.MachineInstallerSupport }
               else { 'Unknown' }
    $target = $App.Scope
    $migration = $false
    if ($App.Scope -eq 'user' -and $support -eq 'Unavailable' -and $App.MachineInstallerSupport -eq 'Supported') {
        $target = 'machine'; $migration = $true
    }
    $App | Add-Member NoteProperty TargetScope $target -Force
    $App | Add-Member NoteProperty RequiresScopeMigration $migration -Force
    $App | Add-Member NoteProperty ScopeMigrationApproved $false -Force
    $App | Add-Member NoteProperty InstallerSupport $support -Force
    return $App
}

function Get-WauAccentPalette {
    param([string]$UserSid)

    $colorValue = $null
    $paths = @()
    if ($UserSid) { $paths += "Registry::HKEY_USERS\$UserSid\Software\Microsoft\Windows\DWM" }
    $paths += 'HKCU:\Software\Microsoft\Windows\DWM'
    foreach ($path in $paths) {
        try {
            $colorValue = (Get-ItemProperty -LiteralPath $path -Name ColorizationColor -ErrorAction Stop).ColorizationColor
            if ($null -ne $colorValue) { break }
        }
        catch { }
    }

    $red = 0; $green = 120; $blue = 212
    if ($null -ne $colorValue) {
        try {
            $raw = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$colorValue), 0)
            $red = [int](($raw -shr 16) -band 0xFF)
            $green = [int](($raw -shr 8) -band 0xFF)
            $blue = [int]($raw -band 0xFF)
        }
        catch { $red = 0; $green = 120; $blue = 212 }
    }

    $makeColor = {
        param([double]$factor, [bool]$towardWhite)
        $target = if ($towardWhite) { 255 } else { 0 }
        $r = [int][Math]::Round($red + (($target - $red) * $factor))
        $g = [int][Math]::Round($green + (($target - $green) * $factor))
        $b = [int][Math]::Round($blue + (($target - $blue) * $factor))
        return '#{0:X2}{1:X2}{2:X2}' -f $r, $g, $b
    }
    $luminance = (0.299 * $red) + (0.587 * $green) + (0.114 * $blue)
    return [pscustomobject]@{
        Base = '#{0:X2}{1:X2}{2:X2}' -f $red, $green, $blue
        Hover = & $makeColor 0.12 $true
        Pressed = & $makeColor 0.16 $false
        Text = if ($luminance -gt 160) { '#000000' } else { '#FFFFFF' }
    }
}
function Show-WauScopeMigrationPrompt {
    param($App, [string]$DisplayName)

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    if (-not ('Wau.Native.MigrationTheme' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace Wau.Native {
    public static class MigrationTheme {
        [DllImport("dwmapi.dll", PreserveSig = true)]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
        public static void SetDarkTitleBar(IntPtr hwnd, bool enabled) {
            int value = enabled ? 1 : 0;
            if (DwmSetWindowAttribute(hwnd, 20, ref value, sizeof(int)) != 0)
                DwmSetWindowAttribute(hwnd, 19, ref value, sizeof(int));
        }
    }
}
"@ -ErrorAction Stop
    }

    $dark = $false
    $themePaths = @()
    if ($App.UserSid) {
        $themePaths += "Registry::HKEY_USERS\$($App.UserSid)\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    }
    $themePaths += 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    foreach ($themePath in $themePaths) {
        try {
            $value = (Get-ItemProperty -LiteralPath $themePath -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme
            $dark = $value -eq 0
            break
        }
        catch { }
    }

    $accent = Get-WauAccentPalette -UserSid $App.UserSid
    if ($dark) {
        $windowBg = '#202124'; $cardBg = '#292A2D'; $border = '#3C4043'
        $primary = '#F1F3F4'; $secondary = '#BDC1C6'; $muted = '#9AA0A6'
        $warningBg = '#332B1D'; $warningBorder = '#765B22'; $cancelBg = '#303134'
    }
    else {
        $windowBg = '#F7F8FA'; $cardBg = '#FFFFFF'; $border = '#DADCE0'
        $primary = '#202124'; $secondary = '#5F6368'; $muted = '#70757A'
        $warningBg = '#FFF7E0'; $warningBorder = '#F1C75B'; $cancelBg = '#EEF0F2'
    }

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Winget Auto Update" Width="590" SizeToContent="Height"
        ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        Topmost="True" ShowInTaskbar="True" Background="$windowBg"
        FontFamily="Segoe UI Variable Display, Segoe UI">
  <Grid Margin="22">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="$cardBg" BorderBrush="$border" BorderThickness="1"
            CornerRadius="10" Padding="18" Margin="0,0,0,14">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="48"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Width="38" Height="38" CornerRadius="8" Background="$($accent.Base)" VerticalAlignment="Top">
          <TextBlock Text="&#x2197;" Foreground="White" FontSize="23" FontWeight="SemiBold"
                     HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel Grid.Column="1" Margin="13,0,0,0">
          <TextBlock Text="Change installation scope" Foreground="$primary" FontSize="18" FontWeight="SemiBold"/>
          <TextBlock Name="PackageText" Foreground="$secondary" FontSize="13" Margin="0,5,0,0" TextWrapping="Wrap"/>
          <Border Background="$($accent.Base)" CornerRadius="10" Padding="10,4" Margin="0,12,0,0" HorizontalAlignment="Left">
            <TextBlock Text="User  &#x2192;  Machine" Foreground="White" FontSize="12" FontWeight="SemiBold"/>
          </Border>
        </StackPanel>
      </Grid>
    </Border>
    <TextBlock Grid.Row="1" Name="ExplanationText" Foreground="$secondary" FontSize="13"
               TextWrapping="Wrap" LineHeight="19" Margin="3,0,3,14"/>
    <Border Grid.Row="2" Background="$warningBg" BorderBrush="$warningBorder" BorderThickness="1"
            CornerRadius="8" Padding="13" Margin="0,0,0,18">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <TextBlock Text="!" Foreground="#E37400" FontWeight="Bold" FontSize="16"/>
        <TextBlock Grid.Column="1" Name="WarningText" Foreground="$muted" FontSize="12"
                   TextWrapping="Wrap" LineHeight="18"/>
      </Grid>
    </Border>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button Name="CancelButton" Content="Skip" MinWidth="110" Height="36" Margin="0,0,9,0"
              Background="$cancelBg" Foreground="$primary" BorderBrush="$border" BorderThickness="1"
              Padding="14,5" Cursor="Hand" IsCancel="True"/>
      <Button Name="ApproveButton" Content="Install with administrator privileges" MinWidth="245" Height="36"
              Background="$($accent.Base)" Foreground="$($accent.Text)" BorderThickness="0"
              Padding="16,5" Cursor="Hand" IsDefault="True"/>
    </StackPanel>
  </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = Get-WauCleanAppName $App.Name $App.Version }
    $window.FindName('PackageText').Text = "$DisplayName $($App.AvailableVersion) can no longer be updated as a user-scoped installation."
    $window.FindName('WarningText').Text = 'The existing user-scoped installation and personal data will not be removed automatically. Depending on the application, both installations may remain installed.'

    $runsAsSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
    if ($runsAsSystem) {
        # ServiceUI makes the SYSTEM-owned dialog visible in the user session.
        # No elevation is required because the protected worker already owns it.
        $window.FindName('ExplanationText').Text = 'The new version supports only a machine-scoped installation for all users. Confirm that Winget Auto Update may install this version for all users.'
        $window.FindName('ApproveButton').Content = 'Install for all users'
    }
    else {
        $window.FindName('ExplanationText').Text = 'The new version supports only a machine-scoped installation for all users. Windows will request administrator privileges through User Account Control (UAC).'
        $window.FindName('ApproveButton').Content = 'Install with administrator privileges'
    }

    $approved = $false
    $window.FindName('ApproveButton').Add_Click({ $script:WauMigrationApproved = $true; $window.DialogResult = $true })
    $window.FindName('CancelButton').Add_Click({ $script:WauMigrationApproved = $false; $window.DialogResult = $false })
    $window.Add_SourceInitialized({
        $handle = (New-Object Windows.Interop.WindowInteropHelper $window).Handle
        [Wau.Native.MigrationTheme]::SetDarkTitleBar($handle, $dark)
    })
    $window.Add_Loaded({ $window.Activate(); $window.Topmost = $true })
    $script:WauMigrationApproved = $false
    $null = $window.ShowDialog()
    $approved = $script:WauMigrationApproved
    Remove-Variable WauMigrationApproved -Scope Script -ErrorAction SilentlyContinue
    return [bool]$approved
}
function Select-WauApprovedUpdates {
    param([array]$Apps, [scriptblock]$ConfirmMigration)
    foreach ($item in $Apps) {
        if ($item.CanUpdate -ne $true) { continue }
        $app = $item | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        $app | Add-Member NoteProperty ScopeMigrationApproved $false -Force
        if ($app.RequiresScopeMigration) {
            $answer = & $ConfirmMigration $app
            if ($answer -isnot [bool] -or -not $answer) { continue }
            $app.ScopeMigrationApproved = $true
        }
        $app
    }
}

function Get-WauActiveSessionIds {
    if (-not ('Wau.Native.WtsApi' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace Wau.Native {
    public enum WtsConnectState { Active, Connected, ConnectQuery, Shadow, Disconnected, Idle, Listen, Reset, Down, Init }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct WtsSessionInfo {
        public Int32 SessionId;
        public IntPtr StationName;
        public WtsConnectState State;
    }
    public static class WtsApi {
        [DllImport("wtsapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool WTSEnumerateSessions(IntPtr server, Int32 reserved, Int32 version, out IntPtr sessions, out Int32 count);
        [DllImport("wtsapi32.dll")]
        public static extern void WTSFreeMemory(IntPtr memory);
        [DllImport("kernel32.dll")]
        public static extern UInt32 WTSGetActiveConsoleSessionId();
    }
}
"@ -ErrorAction Stop
    }

    $buffer = [IntPtr]::Zero
    $count = 0
    try {
        if (-not [Wau.Native.WtsApi]::WTSEnumerateSessions([IntPtr]::Zero, 0, 1, [ref]$buffer, [ref]$count)) {
            return @()
        }
        $size = [Runtime.InteropServices.Marshal]::SizeOf([type][Wau.Native.WtsSessionInfo])
        $active = @()
        for ($index = 0; $index -lt $count; $index++) {
            $pointer = [IntPtr]::Add($buffer, $index * $size)
            $entry = [Runtime.InteropServices.Marshal]::PtrToStructure($pointer, [type][Wau.Native.WtsSessionInfo])
            if ($entry.State -eq [Wau.Native.WtsConnectState]::Active -and $entry.SessionId -gt 0) {
                $active += [int]$entry.SessionId
            }
        }
        return @($active | Select-Object -Unique)
    }
    finally {
        if ($buffer -ne [IntPtr]::Zero) { [Wau.Native.WtsApi]::WTSFreeMemory($buffer) }
    }
}

function Get-WauInteractiveUser {
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $explorers = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue)
    if ($session -ne 0) {
        $candidates = @($explorers | Where-Object { $_.SessionId -eq $session })
    }
    else {
        try { $activeSessions = @(Get-WauActiveSessionIds) } catch { $activeSessions = @() }
        $candidates = @($explorers | Where-Object { $_.SessionId -in $activeSessions })
        $candidateSessions = @($candidates | ForEach-Object SessionId | Select-Object -Unique)

        if ($candidateSessions.Count -gt 1) {
            $consoleSession = [Wau.Native.WtsApi]::WTSGetActiveConsoleSessionId()
            if ($consoleSession -ne [uint32]::MaxValue -and [int]$consoleSession -in $candidateSessions) {
                $candidates = @($candidates | Where-Object { $_.SessionId -eq [int]$consoleSession })
            }
            else {
                Write-ToLog 'Multiple active interactive sessions detected; user selection is ambiguous.' 'Yellow'
                return $null
            }
        }
        elseif ($candidateSessions.Count -eq 0) {
            # Compatibility fallback when WTS enumeration is unavailable: accept
            # only one unambiguous Explorer session, never an arbitrary first one.
            $allSessions = @($explorers | Where-Object { $_.SessionId -gt 0 } | ForEach-Object SessionId | Select-Object -Unique)
            if ($allSessions.Count -ne 1) { return $null }
            $candidates = @($explorers | Where-Object { $_.SessionId -eq $allSessions[0] })
        }
    }
    if (-not $candidates) { return $null }
    $owner = Invoke-CimMethod -InputObject $candidates[0] -MethodName GetOwnerSid
    if ($owner.ReturnValue -eq 0) { return $owner.Sid }
    return $null
}

function Get-WauInteractiveSessionId {
    param([Parameter(Mandatory=$true)][string]$UserSid)
    if ($UserSid -notmatch '^S-1-(?:5-21|12-1)-\d+-\d+-\d+-\d+$') { return $null }

    $activeSessions = @()
    try { $activeSessions = @(Get-WauActiveSessionIds) } catch { }
    $explorers = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue)
    $matchingSessions = @()
    foreach ($explorer in $explorers) {
        if ($activeSessions.Count -and $explorer.SessionId -notin $activeSessions) { continue }
        $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwnerSid -ErrorAction SilentlyContinue
        if ($owner.ReturnValue -eq 0 -and $owner.Sid -eq $UserSid) { $matchingSessions += [int]$explorer.SessionId }
    }
    $matchingSessions = @($matchingSessions | Where-Object { $_ -gt 0 } | Select-Object -Unique)
    if ($matchingSessions.Count -eq 1) { return [int]$matchingSessions[0] }
    if ($matchingSessions.Count -gt 1) {
        $currentSession = [Diagnostics.Process]::GetCurrentProcess().SessionId
        if ($currentSession -gt 0 -and $currentSession -in $matchingSessions) { return [int]$currentSession }
        $consoleSession = [Wau.Native.WtsApi]::WTSGetActiveConsoleSessionId()
        if ($consoleSession -ne [uint32]::MaxValue -and [int]$consoleSession -in $matchingSessions) { return [int]$consoleSession }
        Write-ToLog "Multiple active sessions found for $UserSid; refusing ambiguous launch." 'Yellow'
    }
    return $null
}
function Write-WauAtomicJson {
    param([string]$Path, $Value)
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        ConvertTo-Json -InputObject $Value -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
    }
    finally { Remove-Item -LiteralPath $temporary -ErrorAction SilentlyContinue }
}

# SYSTEM owns requests; the target user can write only that request's response.
# Never execute scripts, installer arguments or a machine update from a response.
function Invoke-WauUserOperation {
    param([ValidateSet('Scan','Plan','Update')][string]$Operation, [string]$UserSid,
          [array]$Apps = @(), [int]$TimeoutSeconds = 600)
    if (-not [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { throw 'User delegation requires SYSTEM.' }
    if ($UserSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$' -and $UserSid -notmatch '^S-1-12-1-\d+-\d+-\d+-\d+$') { throw 'Invalid target user SID.' }
    $requestId = [guid]::NewGuid().ToString('N')
    $root = Join-Path $Script:WorkingDir 'config\scope-requests'
    $directory = Join-Path $root $requestId
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    try {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($sid in @('S-1-5-18','S-1-5-32-544', $UserSid)) {
            $rights = if ($sid -eq $UserSid) { 'ReadAndExecute' } else { 'FullControl' }
            $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid), $rights, 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        }
        Set-Acl -LiteralPath $directory -AclObject $acl -ErrorAction Stop
        $responseDir = New-Item -ItemType Directory -Path (Join-Path $directory 'response') -ErrorAction Stop
        $responseAcl = Get-Acl -LiteralPath $responseDir.FullName
        $responseAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($UserSid), 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        Set-Acl -LiteralPath $responseDir.FullName -AclObject $responseAcl -ErrorAction Stop
        Write-WauAtomicJson (Join-Path $directory 'request.json') ([pscustomobject]@{
            RequestId=$requestId; UserSid=$UserSid; Operation=$Operation; Source=$Script:WingetSourceCustom; Apps=@($Apps)
        })
        # Reuse WAU's fixed interactive task. Per-run tasks left orphaned entries
        # behind when a worker or WinGet call stalled.
        $userTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -TaskPath '\WAU\' -ErrorAction Stop
        $readyWatch = [Diagnostics.Stopwatch]::StartNew()
        while ($userTask.State -eq 'Running' -and $readyWatch.Elapsed.TotalSeconds -lt 15) {
            Start-Sleep -Milliseconds 500
            $userTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -TaskPath '\WAU\' -ErrorAction Stop
        }
        if ($userTask.State -eq 'Running') { throw 'The fixed WAU user task is still busy.' }

        Start-ScheduledTask -InputObject $userTask -ErrorAction Stop
        $responsePath = Join-Path $responseDir.FullName 'result.json'
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            if (Test-Path -LiteralPath $responsePath) {
                if ((Get-Item -LiteralPath $responsePath).Length -gt 4MB) { throw 'Oversized user response.' }
                $response = Get-Content -LiteralPath $responsePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
                if ($response.RequestId -ne $requestId -or $response.UserSid -ne $UserSid -or $response.Success -ne $true) { throw "User operation failed: $($response.Error)" }
                return @($response.Apps)
            }
            Start-Sleep -Seconds 1
        }
        throw "User $Operation timed out; no stale inventory will be used."
    }
    finally {
        if ($directory -and $directory.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WauPendingUserOperation {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { return $false }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $root = Join-Path $Script:WorkingDir 'config\scope-requests'
    foreach ($directory in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime)) {
        $requestPath = Join-Path $directory.FullName 'request.json'
        $responsePath = Join-Path $directory.FullName 'response\result.json'
        if (-not (Test-Path -LiteralPath $requestPath) -or (Test-Path -LiteralPath $responsePath)) { continue }
        $response = [pscustomobject]@{RequestId=$directory.Name;UserSid=$sid;Success=$false;Apps=@();Error=''}
        try {
            $request = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
            if ($request.UserSid -ne $sid -or $request.RequestId -ne $directory.Name) { continue }
            $response.RequestId = $request.RequestId
            if ($request.Operation -eq 'Scan') {
                $response.Apps = @(Get-WingetOutdatedApps -src $request.Source -Scope user)
                foreach ($app in $response.Apps) {
                    $userSupport = Get-WauInstallerSupport -App $app -Scope user -Source $request.Source
                    $machineSupport = if ($userSupport -eq 'Unavailable') {
                        Get-WauInstallerSupport -App $app -Scope machine -Source $request.Source
                    } else { 'Unknown' }
                    $app | Add-Member NoteProperty UserInstallerSupport $userSupport -Force
                    $app | Add-Member NoteProperty MachineInstallerSupport $machineSupport -Force
                }
            }
            elseif ($request.Operation -eq 'Plan') {
                $fresh = @(Get-WingetOutdatedApps -src $request.Source -Scope user)
                $planned = @()
                foreach ($selected in @($request.Apps)) {
                    $app = $fresh | Where-Object { $_.Key -eq $selected.Key -and $_.AvailableVersion -eq $selected.AvailableVersion } | Select-Object -First 1
                    if (-not $app) { continue }
                    $userSupport = Get-WauInstallerSupport -App $app -Scope user -Source $request.Source
                    $machineSupport = if ($userSupport -eq 'Unavailable') {
                        Get-WauInstallerSupport -App $app -Scope machine -Source $request.Source
                    } else { 'Unknown' }
                    $planned += [pscustomobject]@{
                        Key=$app.Key; Id=$app.Id; AvailableVersion=$app.AvailableVersion
                        UserInstallerSupport=$userSupport
                        MachineInstallerSupport=$machineSupport
                    }
                }
                $response.Apps = $planned
            }
            elseif ($request.Operation -eq 'Update') {
                $Script:InstallOK = 0
                $fresh = @(Get-WingetOutdatedApps -src $request.Source -Scope user)
                $completed = @()
                foreach ($selected in @($request.Apps)) {
                    $app = $fresh | Where-Object { $_.Key -eq $selected.Key -and $_.AvailableVersion -eq $selected.AvailableVersion } | Select-Object -First 1
                    if (-not $app) { Write-ToLog "Selected user update changed or disappeared: $($selected.Id)" 'Yellow'; continue }
                    $before = $Script:InstallOK
                    Update-App $app -src $request.Source
                    if ($Script:InstallOK -gt $before) { $completed += [pscustomobject]@{Key=$app.Key;Id=$app.Id} }
                }
                $response.Apps = $completed
            }
            else { throw 'Unknown user operation.' }
            $response.Success = $true
        }
        catch {
            $response.Error = $_.Exception.Message
            Write-ToLog "User operation failed: $($response.Error)" 'Red'
        }
        Write-WauAtomicJson -Path $responsePath -Value $response
        return $true
    }
    return $false
}

