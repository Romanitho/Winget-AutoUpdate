<#
.SYNOPSIS
    Updates a single application using WinGet.

.DESCRIPTION
    Performs the complete update process: notification, pre-install mods,
    WinGet upgrade/install with retry logic, post-install mods, result notification.

.PARAMETER app
    PSCustomObject with Name, Id, Version, AvailableVersion properties.
#>
Function Update-App ($app) {

    # Helper function to build winget command parameters
    function Get-WingetParams ($Command, $ModsOverride, $ModsCustom, $ModsArguments) {
        $params = @($Command, "--id", $app.Id, "-e", "--accept-package-agreements", "--accept-source-agreements", "-s", "winget")
        if ($Command -eq "install") { $params += "--force" }

        if ($ModsOverride) {
            return @{ Params = $params + @("--override", $ModsOverride); Log = "$Command (override): $ModsOverride" }
        }
        elseif ($ModsCustom) {
            return @{ Params = $params + @("-h", "--custom", $ModsCustom); Log = "$Command (custom): $ModsCustom" }
        }
        elseif ($ModsArguments) {
            # Parse arguments respecting quotes and spaces
            $argArray = ConvertTo-WingetArgumentArray $ModsArguments
            return @{ Params = $params + $argArray + @("-h"); Log = "$Command (arguments): $ModsArguments" }
        }
        return @{ Params = $params + "-h"; Log = $Command }
    }

    # Get release notes for notification button
    $ReleaseNoteURL = Get-AppInfo $app.Id
    $Button1Text = if ($ReleaseNoteURL) { $NotifLocale.local.outputs.output[10].message } else { $null }

    # Send "updating" notification
    Write-ToLog "Updating $($app.Name) from $($app.Version) to $($app.AvailableVersion)..." "Cyan"
    Start-NotifTask -Title ($NotifLocale.local.outputs.output[2].title -f $app.Name) `
        -Message ($NotifLocale.local.outputs.output[2].message -f $app.Version, $app.AvailableVersion) `
        -MessageType "info" -Balise $app.Name -Button1Action $ReleaseNoteURL -Button1Text $Button1Text

    # Load mods
    $ModsPreInstall, $ModsOverride, $ModsCustom, $ModsArguments, $ModsUpgrade, $ModsInstall, $ModsInstalled, $ModsNotInstalled = Test-Mods $app.Id

    Write-ToLog "##########   WINGET UPGRADE: $($app.Id)   ##########" "Gray"

    # Pre-install mod
    if ($ModsPreInstall) {
        Write-ToLog "Running pre-install mod for $($app.Id)..." "DarkYellow"
        if ((& $ModsPreInstall) -eq $false) {
            Write-ToLog "Pre-install requested skip" "Yellow"
            return
        }
    }

    # Try upgrade first
    $cmd = Get-WingetParams "upgrade" $ModsOverride $ModsCustom $ModsArguments
    Write-ToLog "-> $($cmd.Log)"

    # Capture output to check for pinning
    $upgradeOutput = & $Winget $cmd.Params 2>&1 | Where-Object { $_ -notlike "   *" } | 
        Tee-Object -file $LogFile -Append | Out-String

    # Check if package is pinned or requires explicit upgrade
    # Matches various winget messages indicating pinning or RequireExplicitUpgrade:
    # - "cannot be upgraded using winget"
    # - "require explicit targeting for upgrade"
    # - "package(s) are pinned" or "packages are pinned"
    # - "Please use the method provided by the publisher"
    if ($upgradeOutput -match "cannot be upgraded using winget" -or 
        $upgradeOutput -match "explicit targeting for upgrade" -or
        $upgradeOutput -match "package.*pinned" -or
        $upgradeOutput -match "use the method provided by the publisher") {
        
        Write-ToLog "-> $($app.Name) is pinned or requires explicit upgrade" "Yellow"
        Write-ToLog "-> Skipping automatic upgrade for this package" "Yellow"
        
        # Send notification about pinned package
        Start-NotifTask -Title ($NotifLocale.local.outputs.output[4].title -f $app.Name) `
            -Message ($NotifLocale.local.outputs.output[4].message -f $app.Name) `
            -MessageType "warning" -Balise $app.Name -Button1Action $ReleaseNoteURL -Button1Text $Button1Text
        
        Write-ToLog "##########   FINISHED: $($app.Id)   ##########" "Gray"
        return  # Exit function early - do NOT try install as fallback
    }

    if ($ModsUpgrade) {
        Write-ToLog "Running upgrade mod..." "DarkYellow"
        & $ModsUpgrade
    }

    $ConfirmInstall = Confirm-Installation $app.Id $app.AvailableVersion

    # Fallback to install if upgrade failed (but NOT if pinned - already handled above)
    if (-not $ConfirmInstall) {
        $maxRetry = if (Test-PendingReboot) { Write-ToLog "-> Pending reboot detected, limiting retries" "Yellow"; 1 } else { 2 }

        for ($retry = 1; $retry -le $maxRetry -and -not $ConfirmInstall; $retry++) {
            Write-ToLog "-> Upgrade failed, trying install ($retry/$maxRetry)..." "DarkYellow"

            $cmd = Get-WingetParams "install" $ModsOverride $ModsCustom $ModsArguments
            Write-ToLog "-> $($cmd.Log)"
            & $Winget $cmd.Params | Where-Object { $_ -notlike "   *" } | Tee-Object -file $LogFile -Append

            if ($ModsInstall) {
                Write-ToLog "Running install mod..." "DarkYellow"
                & $ModsInstall
            }

            $ConfirmInstall = Confirm-Installation $app.Id $app.AvailableVersion
        }
    }

    # Post-install mods
    if ($ConfirmInstall -and $ModsInstalled) {
        Write-ToLog "Running post-install mod..." "DarkYellow"
        & $ModsInstalled
    }
    elseif (-not $ConfirmInstall -and $ModsNotInstalled) {
        Write-ToLog "Running failure mod..." "DarkYellow"
        & $ModsNotInstalled
    }

    Write-ToLog "##########   FINISHED: $($app.Id)   ##########" "Gray"

    # Result notification
    if ($ConfirmInstall) {
        Write-ToLog "$($app.Name) updated to $($app.AvailableVersion)!" "Green"
        Start-NotifTask -Title ($NotifLocale.local.outputs.output[3].title -f $app.Name) `
            -Message ($NotifLocale.local.outputs.output[3].message -f $app.AvailableVersion) `
            -MessageType "success" -Balise $app.Name -Button1Action $ReleaseNoteURL -Button1Text $Button1Text
        $Script:InstallOK += 1
    }
    else {
        Write-ToLog "$($app.Name) update failed." "Red"
        Start-NotifTask -Title ($NotifLocale.local.outputs.output[4].title -f $app.Name) `
            -Message $NotifLocale.local.outputs.output[4].message `
            -MessageType "error" -Balise $app.Name -Button1Action $ReleaseNoteURL -Button1Text $Button1Text
    }
}
