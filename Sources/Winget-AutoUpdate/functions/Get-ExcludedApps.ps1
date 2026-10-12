<#
.SYNOPSIS
    Retrieves the list of excluded (blacklisted) applications.

.DESCRIPTION
    Returns application IDs to exclude from automatic updates.
    Supports multi-tier "Mix & Match": combines exclusions from GPO,
    machine-level files (Program Files & ProgramData), and user profiles.
    Falls back to default_excluded_apps.txt only if no custom exclusions are defined.

.OUTPUTS
    Array of application IDs to exclude.
#>
function Get-ExcludedApps {

    $AppIDs = New-Object System.Collections.Generic.List[string]
    $hasCustomExclusions = $false

    # Helper scriptblock to read and clean text files (ignores empty lines and '#' comments)
    $GetValidFileEntries = {
        param([string]$FilePath)
        if (Test-Path $FilePath) {
            Get-Content -Path $FilePath -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and -not $_.StartsWith("#") }
        }
    }

    # 1. GPO Policy (Machine-level via Group Policy / Intune)
    $GPOPath = "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList"
    if (Test-Path $GPOPath) {
        $gpoProps = (Get-Item $GPOPath).Property
        if ($gpoProps) {
            Write-ToLog "-> Excluded apps from GPO detected"
            foreach ($prop in $gpoProps) {
                $id = (Get-ItemPropertyValue $GPOPath -Name $prop -ErrorAction SilentlyContinue)
                if ($id) {
                    $trimmedId = $id.ToString().Trim()
                    if ($trimmedId -and -not $trimmedId.StartsWith("#")) {
                        Write-ToLog "Exclude app (GPO): $trimmedId"
                        $AppIDs.Add($trimmedId)
                        $hasCustomExclusions = $true
                    }
                }
            }
        }
    }

    # 2. Machine Admin File (Program Files / WorkingDir)
    $LocalFile = [System.IO.Path]::Combine($WorkingDir, 'excluded_apps.txt')
    if (Test-Path $LocalFile) {
        $localEntries = & $GetValidFileEntries $LocalFile
        if ($localEntries) {
            Write-ToLog "-> Successfully loaded machine admin excluded apps list: $LocalFile"
            foreach ($entry in $localEntries) {
                $AppIDs.Add($entry)
                $hasCustomExclusions = $true
            }
        }
    }

    # 3. Machine Shared User File (ProgramData - accessible to standard non-admin users)
    if ($env:ProgramData) {
        $ProgramDataFile = [System.IO.Path]::Combine($env:ProgramData, 'Winget-AutoUpdate', 'excluded_apps.txt')
        if (Test-Path $ProgramDataFile) {
            $progDataEntries = & $GetValidFileEntries $ProgramDataFile
            if ($progDataEntries) {
                Write-ToLog "-> Successfully loaded shared user excluded apps list: $ProgramDataFile"
                foreach ($entry in $progDataEntries) {
                    $AppIDs.Add($entry)
                    $hasCustomExclusions = $true
                }
            }
        }
    }

    # 4. User Profile File (%LocalAppData%\Winget-AutoUpdate\excluded_apps.txt or %USERPROFILE%\excluded_apps.txt)
    # Check current user profile or all active user profiles if running in SYSTEM context
    if (-not $Script:IsSystem) {
        $userPaths = @()
        if ($env:LocalAppData) {
            $userPaths += [System.IO.Path]::Combine($env:LocalAppData, 'Winget-AutoUpdate', 'excluded_apps.txt')
        }
        if ($env:USERPROFILE) {
            $userPaths += [System.IO.Path]::Combine($env:USERPROFILE, 'excluded_apps.txt')
        }
        foreach ($uPath in $userPaths) {
            if (Test-Path $uPath) {
                $userEntries = & $GetValidFileEntries $uPath
                if ($userEntries) {
                    Write-ToLog "-> Successfully loaded user profile excluded apps list: $uPath"
                    foreach ($entry in $userEntries) {
                        $AppIDs.Add($entry)
                        $hasCustomExclusions = $true
                    }
                }
            }
        }
    }
    else {
        # Running as SYSTEM: scan user profile directories
        $userDrive = if ($env:SystemDrive) { $env:SystemDrive } else { "C:" }
        $userExclusionFiles = @(
            Get-ChildItem -Path "$userDrive\Users\*\AppData\Local\Winget-AutoUpdate\excluded_apps.txt" -ErrorAction SilentlyContinue
            Get-ChildItem -Path "$userDrive\Users\*\excluded_apps.txt" -ErrorAction SilentlyContinue
        )
        foreach ($uf in $userExclusionFiles) {
            $userEntries = & $GetValidFileEntries $uf.FullName
            if ($userEntries) {
                Write-ToLog "-> Successfully loaded user profile excluded apps list: $($uf.FullName)"
                foreach ($entry in $userEntries) {
                    $AppIDs.Add($entry)
                    $hasCustomExclusions = $true
                }
            }
        }
    }

    # 5. Default fallback if no custom exclusions were defined across any tier
    $DefaultFile = [System.IO.Path]::Combine($WorkingDir, 'config', 'default_excluded_apps.txt')
    if (-not $hasCustomExclusions -and (Test-Path $DefaultFile)) {
        Write-ToLog "-> No custom exclusions found. Loading default excluded apps list: $DefaultFile"
        $defaultEntries = & $GetValidFileEntries $DefaultFile
        if ($defaultEntries) {
            foreach ($entry in $defaultEntries) {
                $AppIDs.Add($entry)
            }
        }
    }

    return @($AppIDs | Select-Object -Unique)
}
