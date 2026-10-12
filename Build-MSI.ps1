<#
.SYNOPSIS
    Builds the Winget-AutoUpdate (WAU) MSI installer package using WiX Toolset v5.

.DESCRIPTION
    Automates prerequisite verification: checks for .NET SDK (and installs it via
    winget if missing), installs WiX v5 and required extensions, compiles
    Sources/Wix/build.wxs into WAU.msi, and packages ADMX policy templates.
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER Version
    Semantic version without build number (e.g. '3.0.0').
    Defaults to '3.0.0'.

.PARAMETER BuildNumber
    Build number for the 4-part MSI version (e.g. 1 -> 3.0.0.1).
    Defaults to 1.

.PARAMETER Comment
    Package comment written into MSI ARPCOMMENTS property (e.g. 'STABLE').
    Defaults to 'STABLE'.

.PARAMETER PreRelease
    Set to 1 for pre-release builds, 0 for stable.
    Defaults to 0.

.PARAMETER OutDir
    Output directory for the generated WAU.msi and ADMX zip.
    Defaults to the repository root directory.

.PARAMETER SkipPrereqInstall
    Switch to disable automatic installation of missing prerequisites via winget.

.EXAMPLE
    .\Build-MSI.ps1
    .\Build-MSI.ps1 -Version 3.0.0 -BuildNumber 1
    .\Build-MSI.ps1 -Version 3.0.0 -Comment "RELEASE"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Version = "3.0.0",

    [Parameter(Mandatory = $false)]
    [int]$BuildNumber = 1,

    [Parameter(Mandatory = $false)]
    [string]$Comment = "STABLE",

    [Parameter(Mandatory = $false)]
    [ValidateSet(0, 1)]
    [int]$PreRelease = 0,

    [Parameter(Mandatory = $false)]
    [string]$OutDir = "",

    [Parameter(Mandatory = $false)]
    [switch]$SkipPrereqInstall
)

$ErrorActionPreference = "Stop"

# Ensure OutDir defaults to script location if omitted (safe for Windows PowerShell 5.1)
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = $PSScriptRoot
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Winget-AutoUpdate (WAU) - MSI Build Script       " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------------------------

function Get-WingetPath {
    $cmd = Get-Command "winget" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $systemPath = "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe"
    $userPath = "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"

    try {
        $wingetInfo = (Get-Item $systemPath -ErrorAction Stop).VersionInfo |
            Sort-Object FileVersionRaw -Descending |
            Select-Object -First 1
        if ($wingetInfo.FileName) { return $wingetInfo.FileName }
    }
    catch {}

    if (Test-Path $userPath) { return $userPath }

    return $null
}

function Update-SessionEnvironmentPath {
    $pathsToAdd = New-Object 'System.Collections.Generic.List[string]'

    # 1. Standard .NET directory
    if ($env:ProgramFiles) {
        $dotnetDir = [System.IO.Path]::Combine($env:ProgramFiles, "dotnet")
        if (Test-Path $dotnetDir) { $pathsToAdd.Add($dotnetDir) }
    }

    # 2. .NET Tools directory ($HOME/.dotnet/tools or %USERPROFILE%\.dotnet\tools)
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
    if ($homeDir) {
        $toolsDir = [System.IO.Path]::Combine($homeDir, ".dotnet", "tools")
        if (Test-Path $toolsDir) { $pathsToAdd.Add($toolsDir) }
    }

    # 3. Reload from registry if on Windows
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        try {
            $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
            $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
            foreach ($p in ($machinePath, $userPath -split ';')) {
                if ($p -and (Test-Path $p) -and -not $pathsToAdd.Contains($p)) {
                    $pathsToAdd.Add($p)
                }
            }
        }
        catch {}
    }

    # Merge into $env:PATH
    $currentPaths = $env:PATH -split [System.IO.Path]::PathSeparator
    foreach ($p in $pathsToAdd) {
        if (-not ($currentPaths -contains $p)) {
            $env:PATH = "$p$([System.IO.Path]::PathSeparator)$($env:PATH)"
        }
    }
}

function Test-DotnetSdk {
    Update-SessionEnvironmentPath
    $dotnet = Get-Command "dotnet" -ErrorAction SilentlyContinue
    if (-not $dotnet) { return $false }

    try {
        $sdks = & dotnet --list-sdks 2>$null
        if ($sdks -and $sdks.Count -gt 0) {
            # Ensure at least one SDK is version 8.0 or higher
            foreach ($sdk in $sdks) {
                if ($sdk -match '^(\d+)\.') {
                    if ([int]$matches[1] -ge 8) {
                        return $true
                    }
                }
            }
        }
    }
    catch {}

    return $false
}

# ---------------------------------------------------------------------------
# 1. Check and Install .NET SDK
# ---------------------------------------------------------------------------
Write-Host "`n[1/5] Checking .NET SDK (v8.0+)..." -ForegroundColor Yellow

if (-not (Test-DotnetSdk)) {
    Write-Host "  .NET 8.0+ SDK was not detected." -ForegroundColor DarkYellow

    if ($SkipPrereqInstall) {
        Write-Error ".NET SDK 8.0 or higher is required. Please install it from https://dotnet.microsoft.com/download"
        exit 1
    }

    $wingetCmd = Get-WingetPath
    if ($wingetCmd) {
        Write-Host "  Found Winget at: $wingetCmd" -ForegroundColor Cyan
        Write-Host "  Attempting to install 'Microsoft.DotNet.SDK.8' via Winget..." -ForegroundColor Cyan

        try {
            $process = Start-Process -FilePath $wingetCmd `
                -ArgumentList "install --id Microsoft.DotNet.SDK.8 --exact --accept-source-agreements --accept-package-agreements" `
                -NoNewWindow -Wait -PassThru

            if ($process.ExitCode -ne 0) {
                Write-Warning "Winget install returned exit code $($process.ExitCode)."
            }
        }
        catch {
            Write-Warning "Winget installation failed: $($_.Exception.Message)"
        }

        # Refresh PATH and re-test
        Update-SessionEnvironmentPath
        if (-not (Test-DotnetSdk)) {
            Write-Error ".NET SDK installation via Winget did not succeed or is not yet detected.`nPlease install .NET 8.0 SDK manually from https://dotnet.microsoft.com/download and restart your terminal."
            exit 1
        }
        Write-Host "  .NET SDK successfully installed and verified!" -ForegroundColor Green
    }
    else {
        Write-Error "Neither .NET 8.0 SDK nor Winget were found.`nPlease install .NET 8.0 SDK manually from https://dotnet.microsoft.com/download"
        exit 1
    }
}

$dotnetVer = (& dotnet --version 2>$null)
Write-Host "  Found .NET SDK: $dotnetVer" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 2. Check / Install WiX Toolset v5 CLI
# ---------------------------------------------------------------------------
Write-Host "`n[2/5] Checking WiX Toolset v5..." -ForegroundColor Yellow
Update-SessionEnvironmentPath

# WiX extensions also use NuGet. A missing source must be fixed before either
# the CLI or its extensions can be installed.
$nugetSources = @(& dotnet nuget list source --format Short 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read NuGet sources for the current user. Check access to NuGet.Config and run 'dotnet nuget list source' in this terminal."
}
if (-not @($nugetSources | Where-Object { "$_" -match '^\s*E\s+\S' }).Count) {
    if (@($nugetSources | Where-Object { "$_" -match '^\s*D\s+\S' }).Count) {
        throw "All NuGet sources are disabled. Enable your approved source before building."
    }
    Write-Host "  No NuGet source configured for this user. Adding nuget.org..." -ForegroundColor DarkYellow
    & dotnet nuget add source 'https://api.nuget.org/v3/index.json' --name nuget.org
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to add nuget.org as a NuGet source. Configure an approved source and retry."
    }
    $nugetSources = @(& dotnet nuget list source --format Short 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not @($nugetSources | Where-Object { "$_" -match '^\s*E\s+\S' }).Count) {
        throw "No enabled NuGet source is visible after adding nuget.org."
    }
}

$wix = Get-Command "wix" -ErrorAction SilentlyContinue
if (-not $wix) {
    $globalTools = @(& dotnet tool list --global 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect .NET global tools for the current user." }
    $toolAction = if (@($globalTools | Where-Object { "$_" -match '^\s*wix\s+\S' }).Count) { 'update' } else { 'install' }
    Write-Host "  WiX CLI tool not found. Running 'dotnet tool $toolAction --global wix --version 5.0.1'..." -ForegroundColor DarkYellow
    & dotnet tool $toolAction --global wix --version 5.0.1
    if ($LASTEXITCODE -ne 0) {
        throw "WiX $toolAction failed. Check the NuGet error above; the PATH is not the cause until installation succeeds."
    }

    Update-SessionEnvironmentPath
    $wix = Get-Command "wix" -ErrorAction SilentlyContinue
    if (-not $wix) {
        $toolsFolder = [System.IO.Path]::Combine($env:USERPROFILE, '.dotnet', 'tools')
        throw "WiX installation succeeded, but wix.exe is not visible for this user. Check '$toolsFolder' and the current process PATH."
    }
}
$wixVersion = & wix --version
if ($LASTEXITCODE -ne 0) { throw "WiX CLI could not start for the current user." }
Write-Host "  Found WiX CLI version: $wixVersion" -ForegroundColor Green
# ---------------------------------------------------------------------------
# 3. Ensure WiX Extensions (Util & UI) are registered
# ---------------------------------------------------------------------------
Write-Host "`n[3/5] Checking WiX Extensions..." -ForegroundColor Yellow
Write-Host "  Registering WixToolset.UI.wixext/5.0.1..." -ForegroundColor Gray
& wix extension add WixToolset.UI.wixext/5.0.1 -g 2>&1 | Out-Null
Write-Host "  Registering WixToolset.Util.wixext/5.0.1..." -ForegroundColor Gray
& wix extension add WixToolset.Util.wixext/5.0.1 -g 2>&1 | Out-Null

# ---------------------------------------------------------------------------
# 4. Compile MSI
# ---------------------------------------------------------------------------
$MsiVersion = "$Version.$BuildNumber"
$wixDir = [System.IO.Path]::Combine($PSScriptRoot, "Sources", "Wix")
$buildWxs = [System.IO.Path]::Combine($wixDir, "build.wxs")
$msiOut = [System.IO.Path]::Combine($OutDir, "WAU.msi")

if (-not (Test-Path $buildWxs)) {
    Write-Error "Could not find build.wxs at expected location: $buildWxs"
    exit 1
}

Write-Host "`n[4/5] Building WAU.msi (Version: $MsiVersion, SemVer: $Version, Comment: $Comment)..." -ForegroundColor Yellow
Push-Location $wixDir
try {
    $wixArgs = @(
        "build",
        "-src", "build.wxs",
        "-ext", "WixToolset.Util.wixext",
        "-ext", "WixToolset.UI.wixext",
        "-out", $msiOut,
        "-arch", "x64",
        "-d", "Version=$MsiVersion",
        "-d", "NextSemVer=$Version",
        "-d", "Comment=$Comment",
        "-d", "PreRelease=$PreRelease"
    )
    & wix @wixArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Error "WiX build failed with exit code $LASTEXITCODE."
        exit $LASTEXITCODE
    }
}
finally {
    Pop-Location
}

if (Test-Path $msiOut) {
    $hash = (Get-FileHash -Path $msiOut -Algorithm SHA256).Hash
    $sizeMb = [math]::Round(((Get-Item $msiOut).Length / 1MB), 2)
    Write-Host "  [SUCCESS] Created: $msiOut ($sizeMb MB)" -ForegroundColor Green
    Write-Host "  SHA256: $hash" -ForegroundColor Cyan
} else {
    Write-Error "MSI file was not created at $msiOut"
    exit 1
}

# ---------------------------------------------------------------------------
# 5. Packaging ADMX Templates
# ---------------------------------------------------------------------------
Write-Host "`n[5/5] Packaging ADMX Policy Templates..." -ForegroundColor Yellow
$admxSourceDir = [System.IO.Path]::Combine($PSScriptRoot, "Sources", "Policies", "ADMX")
$admxFile = [System.IO.Path]::Combine($admxSourceDir, "WAU.admx")
$admxZip = [System.IO.Path]::Combine($OutDir, "WAU_ADMX.zip")

if (Test-Path $admxFile) {
    try {
        $content = Get-Content $admxFile -Raw
        if ($content -match 'revision="([\d\.]+)"') {
            $admxZip = [System.IO.Path]::Combine($OutDir, "WAU_ADMX_$($matches[1]).zip")
        }
    } catch {}

    if (Test-Path $admxZip) { Remove-Item $admxZip -Force }
    Compress-Archive -Path $admxSourceDir -DestinationPath $admxZip -Force
    $admxHash = (Get-FileHash -Path $admxZip -Algorithm SHA256).Hash
    Write-Host "  [SUCCESS] Created: $admxZip" -ForegroundColor Green
    Write-Host "  SHA256: $admxHash" -ForegroundColor Cyan
}

Write-Host "`n==================================================" -ForegroundColor Green
Write-Host " Build finished successfully!                    " -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
