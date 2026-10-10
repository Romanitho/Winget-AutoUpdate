<#
.SYNOPSIS
    Updates a single application using WinGet.

.DESCRIPTION
    Runs a scope-bound WinGet upgrade (explicitly approved migration: install),
    verifies the installed version in that scope, and reports the result.

.PARAMETER app
    PSCustomObject with Name, Id, Version, AvailableVersion properties.

.PARAMETER src
    The WinGet source to use (e.g. 'winget', 'msstore'). Defaults to 'winget'.
#>
Function Update-App ($app, $src = "winget") {
    # Every update is tied to its installed scope.
    if ($app.Scope -notin @('user', 'machine')) {
        Write-ToLog "Refusing update without verified scope: $($app.Id)" 'Red'
        return
    }
    $targetScope = $app.Scope
    $migration = $app.Scope -eq 'user' -and $app.TargetScope -eq 'machine'
    if ($migration) {
        if ($app.ScopeMigrationApproved -ne $true) {
            Write-ToLog "Scope migration not approved: $($app.Id)" 'Yellow'; return
        }
        if ((Get-WauInstallerSupport $app user $src) -ne 'Unavailable' -or
            (Get-WauInstallerSupport $app machine $src) -ne 'Supported') {
            Write-ToLog "Installer scope changed or could not be verified; migration cancelled: $($app.Id)" 'Yellow'; return
        }
        $targetScope = 'machine'
    }
    # An explicitly approved user-to-machine migration starts in the interactive
    # user session so Windows can display the installer's UAC consent dialog.
    if (($targetScope -eq 'machine') -ne $Script:IsSystem -and -not ($migration -and $app.ScopeMigrationApproved)) {
        Write-ToLog "Wrong execution context for $($app.Id) ($targetScope)" 'Red'; return
    }
    if ($targetScope -eq 'user' -and $app.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
        Write-ToLog "Wrong user for $($app.Id)" 'Red'; return
    }
    if ([string]::IsNullOrWhiteSpace($src)) {
        $src = "winget"
    }
    else {
        $src = $src.Trim()
    }

    # Helper function to build winget command parameters
    function Get-WingetParams ($Command, $ModsArguments) {
        $params = @($Command, "--id", $app.Id, "-e", "--accept-package-agreements", "--accept-source-agreements", "-s", $src,
            '--scope', $targetScope, '--version', $app.AvailableVersion, '--disable-interactivity')
        if ($Command -eq 'upgrade' -and $app.Version -eq 'Unknown') { $params += '--include-unknown' }

        if ($ModsArguments) {
            $argArray = ConvertTo-WingetArgumentArray $ModsArguments
            return @{ Params = $params + $argArray + @('-h'); Log = "$Command (arguments): $ModsArguments" }
        }
        return @{ Params = $params + "-h"; Log = $Command }
    }

    # Load mods
    $ModsPreInstall, $ModsOverride, $ModsCustom, $ModsArguments, $ModsUpgrade, $ModsInstall, $ModsInstalled, $ModsNotInstalled = Test-Mods $app.Id

    # Custom installer switches can override ALLUSERS/scope behind WinGet's back.
    # Do not run those in this scope-preserving pipeline.
    if ($ModsOverride -or $ModsCustom -or $ModsPreInstall -or $ModsUpgrade -or $ModsInstall -or $ModsInstalled -or $ModsNotInstalled) {
        Write-ToLog "Update skipped: installer mods require manual scope review ($($app.Id))." 'Yellow'; return
    }
    if ($ModsArguments) {
        $arguments = @(ConvertTo-WingetArgumentArray $ModsArguments)
        # Allow only known non-scope-changing options, with one value where needed.
        $valid = $true
        for ($i=0; $i -lt $arguments.Count; $i++) {
            if ($arguments[$i] -eq '--skip-dependencies') { continue }
            if ($arguments[$i] -in @('--locale', '--architecture', '-a')) {
                $i++
                if ($i -ge $arguments.Count -or $arguments[$i] -notmatch '^[A-Za-z0-9-]+$') { $valid = $false; break }
            }
            else { $valid = $false; break }
        }
        if (-not $valid) {
            Write-ToLog "Update skipped: mod would override the verified update plan ($($app.Id))." 'Yellow'; return
        }
    }

    # Get release notes for notification button
    $ReleaseNoteURL = Get-AppInfo $app.Id $src
    $Button1Text = if ($ReleaseNoteURL) { $NotifLocale.local.outputs.output[10].message } else { $null }

    # Send "updating" notification
    Write-ToLog "Updating $($app.Name) from $($app.Version) to $($app.AvailableVersion)..." "Cyan"
    Start-NotifTask -Title ($NotifLocale.local.outputs.output[2].title -f $app.Name) `
        -Message ($NotifLocale.local.outputs.output[2].message -f $app.Version, $app.AvailableVersion) `
        -MessageType "info" -Balise $app.Name -Button1Action $ReleaseNoteURL -Button1Text $Button1Text

    Write-ToLog "##########   WINGET UPGRADE: $($app.Id)   ##########" "Gray"

    # Only explicit migration consent permits an install instead of an upgrade.
    $command = if ($migration) { 'install' } else { 'upgrade' }
    $cmd = Get-WingetParams $command $ModsArguments
    Write-ToLog "-> $($cmd.Log)"
    $wingetArgs = $cmd.Params
    & $Winget @wingetArgs | Where-Object { $_ -notlike "   *" } | Tee-Object -file $LogFile -Append
    $updateExitCode = $LASTEXITCODE

    $ConfirmInstall = $updateExitCode -eq 0 -and (Confirm-Installation $app.Id $app.AvailableVersion $src -Scope $targetScope)

    # A failed upgrade stays failed. Never retry as an unscoped/forced install.

    Write-ToLog "##########   FINISHED: $($app.Id)   ##########" "Gray"

    # Result notification
    if ($ConfirmInstall) {
        Write-ToLog "$($app.Name) updated to $($app.AvailableVersion)!" "Green"
        if ($migration) {
            Write-ToLog "Machine installation confirmed. Original user installation was retained: $($app.Id)" "Yellow"
        }
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


