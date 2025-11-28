<#
.SYNOPSIS
    Downloads the latest WAU release and performs self-update.

.DESCRIPTION
    Downloads the WAU MSI package from GitHub and installs it to update
    WAU to the latest version. Sends notifications before and after
    the update process.

.EXAMPLE
    Update-WAU

.NOTES
    Exits the script after update to allow the new version to run.
    Uses MSI installer with silent installation parameters.
#>
function Update-WAU {

    # Setup notification action and button
    $OnClickAction = "https://github.com/Romanitho/$($GitHub_Repo)/releases"
    $Button1Text = $NotifLocale.local.outputs.output[10].message

    # Send "update available" notification
    $Title = $NotifLocale.local.outputs.output[2].title -f "Winget-AutoUpdate"
    $Message = $NotifLocale.local.outputs.output[2].message -f $WAUCurrentVersion, $WAUAvailableVersion
    $MessageType = "info"
    Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text

    # Download and install update
    try {
        Write-ToLog "Downloading the GitHub Repository version $WAUAvailableVersion" "Cyan"

        # Create temporary folder with timestamp for security
        $MsiFolder = "$env:temp\WAU_$(Get-Date -Format yyyyMMddHHmmss)"
        New-Item -ItemType Directory -Path $MsiFolder

        # Download the MSI package
        $MsiFile = Join-Path $MsiFolder "WAU.msi"
        Invoke-RestMethod -Uri "https://github.com/Romanitho/Winget-AutoUpdate/releases/download/v$($WAUAvailableVersion)/WAU.msi" -OutFile $MsiFile

        # Install the update
        Write-ToLog "Updating WAU..." "Yellow"
        Start-Process msiexec.exe -ArgumentList "/i $MsiFile /qn /L*v ""$WorkingDir\logs\WAU-Installer.log"" RUN_WAU=YES INSTALLDIR=""$WorkingDir""" -Wait

        # Send success notification
        Write-ToLog "WAU Update completed. Rerunning WAU..." "Green"
        $Title = $NotifLocale.local.outputs.output[3].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[3].message -f $WAUAvailableVersion
        $MessageType = "success"
        Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text

        # Cleanup temporary files
        Remove-Item $MsiFolder -Recurse -Force

        exit 0
    }

    catch {
        # Send error notification
        $Title = $NotifLocale.local.outputs.output[4].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[4].message
        $MessageType = "error"
        Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text
        Write-ToLog "WAU Update failed" "Red"
    }

}