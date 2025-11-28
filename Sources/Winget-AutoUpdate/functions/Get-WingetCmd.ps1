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

    $systemPath = "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe"
    $userPath = "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"

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
        # System context not found, try user context
    }

    # Fall back to user context
    if (Test-Path $userPath) {
        return $userPath
    }

    return [string]::Empty
}