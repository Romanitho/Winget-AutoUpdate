# Helper functions for testing dual listing mode configuration
# These functions help test the different ways dual listing mode can be configured

function Test-DualListingGPOConfiguration {
    <#
    .SYNOPSIS
    Tests GPO-based dual listing configuration
    
    .DESCRIPTION
    This function tests that dual listing mode can be properly configured via Group Policy
    and that the configuration is correctly read by WAU components.
    #>
    
    param(
        [switch]$EnableDualListing,
        [string[]]$WhitelistApps = @(),
        [string[]]$BlacklistApps = @()
    )
    
    try {
        # Test GPO registry keys
        $gpoPath = "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate"
        
        if (-not (Test-Path $gpoPath)) {
            Write-Warning "GPO registry path not found: $gpoPath"
            return $false
        }
        
        # Check if dual listing is enabled
        $dualListingEnabled = Get-ItemPropertyValue -Path $gpoPath -Name "WAU_UseDualListing" -ErrorAction SilentlyContinue
        
        if ($EnableDualListing -and $dualListingEnabled -ne 1) {
            Write-Warning "Dual listing should be enabled but registry value is: $dualListingEnabled"
            return $false
        }
        
        # Test whitelist configuration
        $whiteListPath = "$gpoPath\WhiteList"
        if ($WhitelistApps.Count -gt 0) {
            if (-not (Test-Path $whiteListPath)) {
                Write-Warning "Whitelist GPO path not found: $whiteListPath"
                return $false
            }
            
            $whiteListValues = (Get-Item -Path $whiteListPath).Property
            foreach ($app in $WhitelistApps) {
                if ($app -notin $whiteListValues) {
                    Write-Warning "App '$app' not found in GPO whitelist"
                    return $false
                }
            }
        }
        
        # Test blacklist configuration
        $blackListPath = "$gpoPath\BlackList"
        if ($BlacklistApps.Count -gt 0) {
            if (-not (Test-Path $blackListPath)) {
                Write-Warning "Blacklist GPO path not found: $blackListPath"
                return $false
            }
            
            $blackListValues = (Get-Item -Path $blackListPath).Property
            foreach ($app in $BlacklistApps) {
                if ($app -notin $blackListValues) {
                    Write-Warning "App '$app' not found in GPO blacklist"
                    return $false
                }
            }
        }
        
        Write-Host "GPO dual listing configuration test passed" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Error testing GPO configuration: $_"
        return $false
    }
}

function Test-DualListingRegistryConfiguration {
    <#
    .SYNOPSIS
    Tests registry-based dual listing configuration
    
    .DESCRIPTION
    This function tests that dual listing mode can be properly configured via registry
    and that the configuration is correctly read by WAU components.
    #>
    
    param(
        [switch]$EnableDualListing,
        [string]$InstallLocation = "C:\Program Files\WAU"
    )
    
    try {
        # Test main WAU registry keys
        $wauPaths = @(
            "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate",
            "HKLM:\SOFTWARE\WOW6432Node\Romanitho\Winget-AutoUpdate"
        )
        
        $configFound = $false
        foreach ($path in $wauPaths) {
            if (Test-Path $path) {
                $config = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
                if ($config) {
                    $configFound = $true
                    
                    if ($EnableDualListing -and $config.WAU_UseDualListing -ne 1) {
                        Write-Warning "Dual listing should be enabled but registry value is: $($config.WAU_UseDualListing)"
                        return $false
                    }
                    
                    if ($config.InstallLocation -ne $InstallLocation) {
                        Write-Warning "Install location mismatch. Expected: $InstallLocation, Got: $($config.InstallLocation)"
                        return $false
                    }
                    
                    break
                }
            }
        }
        
        if (-not $configFound) {
            Write-Warning "WAU registry configuration not found"
            return $false
        }
        
        Write-Host "Registry dual listing configuration test passed" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Error testing registry configuration: $_"
        return $false
    }
}

function Test-DualListingFileConfiguration {
    <#
    .SYNOPSIS
    Tests file-based dual listing configuration
    
    .DESCRIPTION
    This function tests that dual listing mode can be properly configured via files
    and that the configuration is correctly read by WAU components.
    #>
    
    param(
        [string]$InstallLocation = "C:\Program Files\WAU",
        [string[]]$WhitelistApps = @(),
        [string[]]$BlacklistApps = @()
    )
    
    try {
        # Test whitelist file
        $whiteListFile = Join-Path $InstallLocation "included_apps.txt"
        if ($WhitelistApps.Count -gt 0) {
            if (-not (Test-Path $whiteListFile)) {
                Write-Warning "Whitelist file not found: $whiteListFile"
                return $false
            }
            
            $whiteListContent = Get-Content $whiteListFile -ErrorAction SilentlyContinue
            foreach ($app in $WhitelistApps) {
                if ($app -notin $whiteListContent) {
                    Write-Warning "App '$app' not found in whitelist file"
                    return $false
                }
            }
        }
        
        # Test blacklist file
        $blackListFile = Join-Path $InstallLocation "excluded_apps.txt"
        if ($BlacklistApps.Count -gt 0) {
            if (-not (Test-Path $blackListFile)) {
                Write-Warning "Blacklist file not found: $blackListFile"
                return $false
            }
            
            $blackListContent = Get-Content $blackListFile -ErrorAction SilentlyContinue
            foreach ($app in $BlacklistApps) {
                if ($app -notin $blackListContent) {
                    Write-Warning "App '$app' not found in blacklist file"
                    return $false
                }
            }
        }
        
        Write-Host "File dual listing configuration test passed" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Error testing file configuration: $_"
        return $false
    }
}

function New-DualListingTestEnvironment {
    <#
    .SYNOPSIS
    Creates a test environment for dual listing mode
    
    .DESCRIPTION
    This function sets up a complete test environment for dual listing mode,
    including registry entries, files, and GPO settings.
    #>
    
    param(
        [string]$TestPath = $env:TEMP,
        [string[]]$WhitelistApps = @("Microsoft.PowerShell", "Microsoft.VisualStudioCode"),
        [string[]]$BlacklistApps = @("Mozilla.Firefox", "Google.Chrome"),
        [switch]$EnableGPO,
        [switch]$EnableRegistry,
        [switch]$EnableFiles
    )
    
    $testDir = Join-Path $TestPath "WAU-DualListingTest-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    
    try {
        if ($EnableFiles) {
            # Create whitelist file
            if ($WhitelistApps.Count -gt 0) {
                $whiteListFile = Join-Path $testDir "included_apps.txt"
                $WhitelistApps | Out-File -FilePath $whiteListFile -Encoding UTF8
                Write-Host "Created whitelist file: $whiteListFile" -ForegroundColor Green
            }
            
            # Create blacklist file
            if ($BlacklistApps.Count -gt 0) {
                $blackListFile = Join-Path $testDir "excluded_apps.txt"
                $BlacklistApps | Out-File -FilePath $blackListFile -Encoding UTF8
                Write-Host "Created blacklist file: $blackListFile" -ForegroundColor Green
            }
        }
        
        if ($EnableRegistry) {
            # Create registry entries (requires admin privileges)
            $registryPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
            
            if (-not (Test-Path $registryPath)) {
                New-Item -Path $registryPath -Force | Out-Null
            }
            
            Set-ItemProperty -Path $registryPath -Name "WAU_UseDualListing" -Value 1 -Type DWord
            Set-ItemProperty -Path $registryPath -Name "InstallLocation" -Value $testDir -Type String
            
            Write-Host "Created registry entries at: $registryPath" -ForegroundColor Green
        }
        
        if ($EnableGPO) {
            # Create GPO registry entries (requires admin privileges)
            $gpoPath = "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate"
            
            if (-not (Test-Path $gpoPath)) {
                New-Item -Path $gpoPath -Force | Out-Null
            }
            
            Set-ItemProperty -Path $gpoPath -Name "WAU_ActivateGPOManagement" -Value 1 -Type DWord
            Set-ItemProperty -Path $gpoPath -Name "WAU_UseDualListing" -Value 1 -Type DWord
            
            # Create whitelist GPO entries
            if ($WhitelistApps.Count -gt 0) {
                $whiteListGPOPath = "$gpoPath\WhiteList"
                if (-not (Test-Path $whiteListGPOPath)) {
                    New-Item -Path $whiteListGPOPath -Force | Out-Null
                }
                
                for ($i = 0; $i -lt $WhitelistApps.Count; $i++) {
                    Set-ItemProperty -Path $whiteListGPOPath -Name ($i + 1) -Value $WhitelistApps[$i] -Type String
                }
            }
            
            # Create blacklist GPO entries
            if ($BlacklistApps.Count -gt 0) {
                $blackListGPOPath = "$gpoPath\BlackList"
                if (-not (Test-Path $blackListGPOPath)) {
                    New-Item -Path $blackListGPOPath -Force | Out-Null
                }
                
                for ($i = 0; $i -lt $BlacklistApps.Count; $i++) {
                    Set-ItemProperty -Path $blackListGPOPath -Name ($i + 1) -Value $BlacklistApps[$i] -Type String
                }
            }
            
            Write-Host "Created GPO entries at: $gpoPath" -ForegroundColor Green
        }
        
        return [PSCustomObject]@{
            TestDirectory = $testDir
            WhitelistApps = $WhitelistApps
            BlacklistApps = $BlacklistApps
            GPOEnabled = $EnableGPO
            RegistryEnabled = $EnableRegistry
            FilesEnabled = $EnableFiles
        }
    }
    catch {
        Write-Error "Error creating test environment: $_"
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Remove-DualListingTestEnvironment {
    <#
    .SYNOPSIS
    Cleans up the test environment for dual listing mode
    
    .DESCRIPTION
    This function removes all test artifacts created by New-DualListingTestEnvironment.
    #>
    
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$TestEnvironment
    )
    
    try {
        # Remove test directory
        if (Test-Path $TestEnvironment.TestDirectory) {
            Remove-Item -Path $TestEnvironment.TestDirectory -Recurse -Force
            Write-Host "Removed test directory: $($TestEnvironment.TestDirectory)" -ForegroundColor Green
        }
        
        # Remove registry entries if they were created
        if ($TestEnvironment.RegistryEnabled) {
            $registryPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
            if (Test-Path $registryPath) {
                Remove-ItemProperty -Path $registryPath -Name "WAU_UseDualListing" -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $registryPath -Name "InstallLocation" -ErrorAction SilentlyContinue
                Write-Host "Removed registry test entries" -ForegroundColor Green
            }
        }
        
        # Remove GPO entries if they were created
        if ($TestEnvironment.GPOEnabled) {
            $gpoPath = "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate"
            if (Test-Path $gpoPath) {
                Remove-Item -Path $gpoPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "Removed GPO test entries" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Warning "Error cleaning up test environment: $_"
    }
}

function Invoke-DualListingModeTests {
    <#
    .SYNOPSIS
    Runs comprehensive tests for dual listing mode
    
    .DESCRIPTION
    This function runs all the dual listing mode tests and provides a summary report.
    #>
    
    param(
        [switch]$IncludeIntegrationTests,
        [switch]$IncludePerformanceTests,
        [string]$TestResultsPath = $null
    )
    
    $testResults = @()
    
    try {
        Write-Host "Starting Dual Listing Mode Tests..." -ForegroundColor Cyan
        
        # Run Pester tests
        $pesterParams = @{
            Path = ".\Tests\DualListingMode.Tests.ps1"
            PassThru = $true
            Show = 'All'
        }
        
        if ($TestResultsPath) {
            $pesterParams.OutputFile = $TestResultsPath
            $pesterParams.OutputFormat = 'NUnitXml'
        }
        
        $testResults += Invoke-Pester @pesterParams
        
        # Run integration tests if requested
        if ($IncludeIntegrationTests) {
            Write-Host "Running integration tests..." -ForegroundColor Yellow
            
            # Test GPO configuration
            $gpoTestResult = Test-DualListingGPOConfiguration -EnableDualListing
            $testResults += [PSCustomObject]@{
                TestName = "GPO Configuration Test"
                Result = $gpoTestResult
                Type = "Integration"
            }
            
            # Test Registry configuration
            $registryTestResult = Test-DualListingRegistryConfiguration -EnableDualListing
            $testResults += [PSCustomObject]@{
                TestName = "Registry Configuration Test"
                Result = $registryTestResult
                Type = "Integration"
            }
            
            # Test File configuration
            $fileTestResult = Test-DualListingFileConfiguration -WhitelistApps @("Microsoft.PowerShell") -BlacklistApps @("Mozilla.Firefox")
            $testResults += [PSCustomObject]@{
                TestName = "File Configuration Test"
                Result = $fileTestResult
                Type = "Integration"
            }
        }
        
        # Generate summary report
        $passedTests = $testResults | Where-Object { $_.Result -eq $true -or $_.Passed -gt 0 }
        $failedTests = $testResults | Where-Object { $_.Result -eq $false -or $_.Failed -gt 0 }
        
        Write-Host "`n=== DUAL LISTING MODE TEST SUMMARY ===" -ForegroundColor Cyan
        Write-Host "Total Tests: $($testResults.Count)" -ForegroundColor White
        Write-Host "Passed: $($passedTests.Count)" -ForegroundColor Green
        Write-Host "Failed: $($failedTests.Count)" -ForegroundColor Red
        
        if ($failedTests.Count -gt 0) {
            Write-Host "`nFailed Tests:" -ForegroundColor Red
            $failedTests | ForEach-Object {
                Write-Host "  - $($_.TestName)" -ForegroundColor Red
            }
        }
        
        return $testResults
    }
    catch {
        Write-Error "Error running dual listing mode tests: $_"
        return $null
    }
}

# Functions are automatically available when dot-sourced
# No Export-ModuleMember needed for script files
