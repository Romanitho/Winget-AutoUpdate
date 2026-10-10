<#
.SYNOPSIS
    Retrieves the path to the Winget executable.

.DESCRIPTION
    Locates winget.exe from system context (WindowsApps) or user context.
    Returns the most recent version when multiple exist.

.OUTPUTS
    String: Full path to winget.exe, or empty if not found.
#>
Function Get-WingetCmd {
    [OutputType([String])]

    $programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
    $systemPath = "$programFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe"

    # Try system context first (newest version)
    try {
        $WingetInfo = (Get-Item $systemPath -ErrorAction Stop).VersionInfo |
            Sort-Object FileVersionRaw -Descending |
            Select-Object -First 1

        if ($WingetInfo.FileName) {
            return $WingetInfo.FileName
        }
    }
    catch {
        # System context not found
    }

    # Security check: Never fall back to user profile when running as SYSTEM (prevents unprivileged LPE)
    $isSystem = if ($null -ne $Script:IsSystem) { $Script:IsSystem }
                else { [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem }
    if ($isSystem) {
        return [string]::Empty
    }

    # Fall back to user context only when running as standard user
    $userPath = "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"
    if (Test-Path $userPath) {
        return $userPath
    }

    return [string]::Empty
}