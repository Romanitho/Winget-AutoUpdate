#!/usr/bin/env pwsh
<#
.SYNOPSIS
Quick test script for dual listing mode demonstration

.DESCRIPTION
This script demonstrates dual listing mode functionality without requiring full WAU installation.
It creates a mock scenario and tests the logic directly.

.PARAMETER ShowConfiguration
Shows the current dual listing configuration

.PARAMETER TestOnly
Only runs the logic test without setting up configuration

.EXAMPLE
.\Test-DualListingQuick.ps1

.EXAMPLE
.\Test-DualListingQuick.ps1 -ShowConfiguration
#>

param(
    [switch]$ShowConfiguration,
    [switch]$TestOnly
)

# Test configuration
$TestApps = @{
    "RProject.Rtools" = @{
        Name = "Rtools"
        Version = "4.0.0"
        AvailableVersion = "4.2.0"
        ExpectedResult = "BLOCKED"  # In both whitelist and blacklist, blacklist wins
    }
    "Adobe.Acrobat.Reader.64-bit" = @{
        Name = "Adobe Acrobat Reader DC"
        Version = "23.001.20093"
        AvailableVersion = "23.003.20201"
        ExpectedResult = "ALLOWED"  # In whitelist, not in blacklist
    }
}

function Write-TestOutput {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    $color = switch ($Level) {
        "Info" { "White" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        "Success" { "Green" }
        "Header" { "Cyan" }
    }
    
    Write-Host $Message -ForegroundColor $color
}

function Show-DualListingConfiguration {
    Write-TestOutput "=== Current Dual Listing Configuration ===" -Level "Header"
    
    $wauRegPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
    $wauPolicyPath = "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate"
    
    try {
        # Check dual listing mode
        $dualListingEnabled = Get-ItemPropertyValue -Path $wauRegPath -Name "WAU_UseDualListing" -ErrorAction SilentlyContinue
        Write-TestOutput "Dual Listing Mode: $(if ($dualListingEnabled -eq 1) { 'ENABLED' } else { 'DISABLED' })" -Level $(if ($dualListingEnabled -eq 1) { "Success" } else { "Warning" })
        
        # Check GPO activation
        $gpoEnabled = Get-ItemPropertyValue -Path $wauPolicyPath -Name "WAU_ActivateGPOManagement" -ErrorAction SilentlyContinue
        Write-TestOutput "GPO Management: $(if ($gpoEnabled -eq 1) { 'ENABLED' } else { 'DISABLED' })" -Level $(if ($gpoEnabled -eq 1) { "Success" } else { "Warning" })
        
        # Show whitelist
        $whitelistPath = "$wauPolicyPath\WhiteList"
        if (Test-Path $whitelistPath) {
            Write-TestOutput "`nWhitelist entries:" -Level "Info"
            $whitelistEntries = Get-Item -Path $whitelistPath | Select-Object -ExpandProperty Property
            foreach ($entry in $whitelistEntries) {
                $value = Get-ItemPropertyValue -Path $whitelistPath -Name $entry
                Write-TestOutput "  ✓ $value" -Level "Success"
            }
        } else {
            Write-TestOutput "`nWhitelist: NOT CONFIGURED" -Level "Warning"
        }
        
        # Show blacklist
        $blacklistPath = "$wauPolicyPath\BlackList"
        if (Test-Path $blacklistPath) {
            Write-TestOutput "`nBlacklist entries:" -Level "Info"
            $blacklistEntries = Get-Item -Path $blacklistPath | Select-Object -ExpandProperty Property
            foreach ($entry in $blacklistEntries) {
                $value = Get-ItemPropertyValue -Path $blacklistPath -Name $entry
                Write-TestOutput "  ✗ $value" -Level "Error"
            }
        } else {
            Write-TestOutput "`nBlacklist: NOT CONFIGURED" -Level "Warning"
        }
    }
    catch {
        Write-TestOutput "Error reading configuration: $($_.Exception.Message)" -Level "Error"
    }
}

function Test-DualListingLogic {
    Write-TestOutput "`n=== Testing Dual Listing Logic ===" -Level "Header"
    
    # Import required functions
    $functionsPath = Join-Path $PSScriptRoot "..\Sources\Winget-AutoUpdate\functions"
    
    try {
        . "$functionsPath\Get-DualListApps.ps1"
        . "$functionsPath\Get-IncludedApps.ps1"
        . "$functionsPath\Get-ExcludedApps.ps1"
        
        # Mock Write-ToLog function
        function Write-ToLog { 
            param($Message, $Color) 
            Write-TestOutput "[WAU] $Message" -Level "Info" 
        }
        
        # Set global variables for GPO mode
        $global:GPOList = $true
        $global:URIList = $false
        $global:WorkingDir = "C:\Program Files\WAU"
        
        # Create mock outdated apps
        $mockOutdatedApps = @()
        foreach ($appId in $TestApps.Keys) {
            $app = $TestApps[$appId]
            $mockOutdatedApps += [PSCustomObject]@{
                Id = $appId
                Name = $app.Name
                Version = $app.Version
                AvailableVersion = $app.AvailableVersion
            }
        }
        
        Write-TestOutput "Created mock outdated apps: $($mockOutdatedApps.Count)" -Level "Info"
        
        # Test the dual listing logic
        $result = Get-DualListApps -OutdatedApps $mockOutdatedApps
        
        Write-TestOutput "`n=== Test Results ===" -Level "Header"
        
        $allTestsPassed = $true
        
        foreach ($appResult in $result) {
            $appId = $appResult.App.Id
            $shouldUpdate = $appResult.ShouldUpdate
            $reason = $appResult.Reason
            $expectedResult = $TestApps[$appId].ExpectedResult
            
            Write-TestOutput "`nApp: $appId" -Level "Info"
            Write-TestOutput "Expected: $expectedResult" -Level "Info"
            Write-TestOutput "Actual: $(if ($shouldUpdate) { 'ALLOWED' } else { 'BLOCKED' })" -Level $(if ($shouldUpdate) { "Success" } else { "Warning" })
            Write-TestOutput "Reason: $reason" -Level "Info"
            
            # Validate expected behavior
            $testPassed = ($expectedResult -eq "ALLOWED" -and $shouldUpdate) -or ($expectedResult -eq "BLOCKED" -and -not $shouldUpdate)
            
            if ($testPassed) {
                Write-TestOutput "Result: ✅ PASS" -Level "Success"
            } else {
                Write-TestOutput "Result: ❌ FAIL" -Level "Error"
                $allTestsPassed = $false
            }
        }
        
        Write-TestOutput "`n=== Final Result ===" -Level "Header"
        if ($allTestsPassed) {
            Write-TestOutput "🎉 All tests PASSED! Dual listing mode is working correctly." -Level "Success"
        } else {
            Write-TestOutput "❌ Some tests FAILED. Check the configuration." -Level "Error"
        }
        
        return $result
    }
    catch {
        Write-TestOutput "Error testing dual listing logic: $($_.Exception.Message)" -Level "Error"
        Write-TestOutput "Stack trace: $($_.Exception.StackTrace)" -Level "Error"
        throw
    }
}

function Initialize-QuickTestConfiguration {
    Write-TestOutput "=== Setting up Quick Test Configuration ===" -Level "Header"
    
    #Requires -RunAsAdministrator
    
    $wauRegPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
    $wauPolicyPath = "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate"
    $whitelistPath = "$wauPolicyPath\WhiteList"
    $blacklistPath = "$wauPolicyPath\BlackList"
    
    try {
        # Create registry paths
        if (-not (Test-Path $wauRegPath)) {
            New-Item -Path $wauRegPath -Force | Out-Null
        }
        if (-not (Test-Path $wauPolicyPath)) {
            New-Item -Path $wauPolicyPath -Force | Out-Null
        }
        if (-not (Test-Path $whitelistPath)) {
            New-Item -Path $whitelistPath -Force | Out-Null
        }
        if (-not (Test-Path $blacklistPath)) {
            New-Item -Path $blacklistPath -Force | Out-Null
        }
        
        # Enable dual listing mode
        Set-ItemProperty -Path $wauRegPath -Name "WAU_UseDualListing" -Value 1 -Type DWord
        Set-ItemProperty -Path $wauPolicyPath -Name "WAU_ActivateGPOManagement" -Value 1 -Type DWord
        Set-ItemProperty -Path $wauPolicyPath -Name "WAU_UseDualListing" -Value 1 -Type DWord
        
        # Add both apps to whitelist
        Set-ItemProperty -Path $whitelistPath -Name "1" -Value "RProject.Rtools" -Type String
        Set-ItemProperty -Path $whitelistPath -Name "2" -Value "Adobe.Acrobat.Reader.64-bit" -Type String
        
        # Add only RProject.Rtools to blacklist (should override whitelist)
        Set-ItemProperty -Path $blacklistPath -Name "1" -Value "RProject.Rtools" -Type String
        
        Write-TestOutput "✅ Configuration setup complete!" -Level "Success"
        Write-TestOutput "Whitelist: RProject.Rtools, Adobe.Acrobat.Reader.64-bit" -Level "Info"
        Write-TestOutput "Blacklist: RProject.Rtools" -Level "Info"
        Write-TestOutput "Expected: RProject.Rtools blocked, Adobe.Acrobat.Reader.64-bit allowed" -Level "Info"
        
    }
    catch {
        Write-TestOutput "Error setting up configuration: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

function Remove-QuickTestConfiguration {
    Write-TestOutput "=== Removing Test Configuration ===" -Level "Header"
    
    $wauPolicyPath = "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate"
    $wauRegPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
    
    try {
        # Remove policy registry entries
        if (Test-Path $wauPolicyPath) {
            Remove-Item -Path $wauPolicyPath -Recurse -Force
            Write-TestOutput "✅ Removed policy registry entries" -Level "Success"
        }
        
        # Remove dual listing registry value
        if (Test-Path $wauRegPath) {
            Remove-ItemProperty -Path $wauRegPath -Name "WAU_UseDualListing" -ErrorAction SilentlyContinue
            Write-TestOutput "✅ Removed dual listing mode setting" -Level "Success"
        }
        
        Write-TestOutput "✅ Cleanup complete!" -Level "Success"
    }
    catch {
        Write-TestOutput "Error during cleanup: $($_.Exception.Message)" -Level "Error"
    }
}

function Main {
    Write-TestOutput "=== Winget-AutoUpdate Dual Listing Mode Quick Test ===" -Level "Header"
    Write-TestOutput "This script demonstrates dual listing mode functionality" -Level "Info"
    Write-TestOutput ""
    
    if ($ShowConfiguration) {
        Show-DualListingConfiguration
        return
    }
    
    if ($TestOnly) {
        Test-DualListingLogic
        return
    }
    
    # Check if running as administrator
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-TestOutput "This script requires Administrator privileges to modify registry" -Level "Error"
        Write-TestOutput "Please run as Administrator or use -TestOnly to test existing configuration" -Level "Warning"
        exit 1
    }
    
    try {
        # Step 1: Setup test configuration
        Initialize-QuickTestConfiguration
        
        # Step 2: Show configuration
        Show-DualListingConfiguration
        
        # Step 3: Test the logic
        Test-DualListingLogic
        
        # Step 4: Cleanup
        $cleanup = Read-Host "`nRemove test configuration? (Y/n)"
        if ($cleanup -ne 'n' -and $cleanup -ne 'N') {
            Remove-QuickTestConfiguration
        }
        
    }
    catch {
        Write-TestOutput "Test failed: $($_.Exception.Message)" -Level "Error"
        exit 1
    }
}

# Run the main function
Main
