function Get-WingetOutdatedApps {
    param([Parameter(Mandatory=$true)][string]$src,
          [ValidateSet('user','machine')][string]$Scope)
    if (-not $Scope) { $Scope = if ($Script:IsSystem) { 'machine' } else { 'user' } }
    if ($Scope -eq 'user' -and $Script:IsSystem) { throw 'User inventory must run as the owning user.' }
    # list reports catalog updates even if the new installer cannot preserve scope.
    $arguments = @('list', '--upgrade-available', '--include-unknown',
        '--source', $src, '--scope', $Scope, '--accept-source-agreements', '--disable-interactivity')
    $details = Test-WauWingetDetails
    if ($details) { $arguments += '--details' }
    $result = Invoke-WauWinget -Arguments $arguments
    if ($result.ExitCode -ne 0 -and $result.ExitCode -ne -1978335212) {
        throw "WinGet inventory failed ($($result.ExitCode)): $($result.Output)"
    }
    $sid = if ($Scope -eq 'user') { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value } else { '' }
    $catalog = if ($details) { @(ConvertFrom-WauWingetDetails -Text $result.Output -Source $src -Upgrade) }
               else { @(ConvertFrom-WauWingetTable -Text $result.Output -Upgrade) }
    foreach ($app in $catalog) {
        $app | Add-Member NoteProperty Scope $Scope
        $app | Add-Member NoteProperty UserSid $sid
        $app | Add-Member NoteProperty Source $src
        $app | Add-Member NoteProperty Key (Get-WauAppKey $app)
        $app
    }
}

