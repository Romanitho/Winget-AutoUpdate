<#
.SYNOPSIS
    Tests whether an application is installed machine-wide (in Program Files or HKLM).

.DESCRIPTION
    Inspects HKLM uninstall registry keys (64-bit and WOW6432Node views) and standard
    Program Files directories to determine if an application was installed
    machine-wide. This handles "hybrid" applications that were installed with
    administrative privileges (e.g. from an admin PowerShell) where the app files
    reside in Program Files but the update was detected via the user context.

    Applications identified as machine-scoped are updated by SYSTEM with full
    administrative elevation, preventing unwanted UAC prompts.

.PARAMETER AppId
    The Winget package identifier (e.g. "WinSCP.WinSCP", "Vivaldi.Vivaldi").

.PARAMETER AppName
    The display name of the application (e.g. "WinSCP 6.1.2", "Vivaldi").

.OUTPUTS
    Boolean: $true if the application is installed machine-wide, $false otherwise.
#>
function Test-IsMachineApp {
    param(
        [Parameter(Mandatory = $false)]
        [string]$AppId = '',

        [Parameter(Mandatory = $false)]
        [string]$AppName = ''
    )

    # 1. Check registry under HKLM (both 64-bit and WOW6432Node views)
    $hklmPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    try {
        $regMatches = Get-ItemProperty -Path $hklmPaths -ErrorAction SilentlyContinue | Where-Object {
            ($AppName -and $_.DisplayName -and ($_.DisplayName -eq $AppName -or $_.DisplayName -like "$AppName*")) -or
            ($AppId -and $_.PSChildName -and ($_.PSChildName -eq $AppId -or $_.PSChildName -like "*$AppId*"))
        }
        if ($regMatches) { return $true }
    }
    catch { }

    # 2. Check filesystem under Program Files directories
    $progDirs = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramW6432
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($dir in $progDirs) {
        $candidatePaths = [System.Collections.Generic.List[string]]::new()
        if ($AppName) {
            $candidatePaths.Add((Join-Path $dir $AppName))
            $baseName = ($AppName -replace '\s+[\d\.]+$', '').Trim()
            if ($baseName) { $candidatePaths.Add((Join-Path $dir $baseName)) }
        }
        if ($AppId -and $AppId.Contains('.')) {
            $candidatePaths.Add((Join-Path $dir $AppId.Split('.')[-1]))
        }

        foreach ($cp in $candidatePaths) {
            if (Test-Path $cp) {
                # Ensure folder actually contains executable binaries (avoids false positives from empty leftover folders)
                $hasExe = @(Get-ChildItem -Path $cp -Filter "*.exe" -File -Recurse -Depth 2 -ErrorAction SilentlyContinue).Count -gt 0
                if ($hasExe) { return $true }
            }
        }
    }

    return $false
}
