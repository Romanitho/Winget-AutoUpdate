#Test script for Pinned Apps functionality
#This script tests the newly added pinning functionality

param(
    [switch]$TestGPO,
    [switch]$TestWingetPins,
    [switch]$TestVersionPatterns,
    [switch]$All
)

# Import required functions
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$FunctionsPath = Join-Path $ScriptPath "Winget-AutoUpdate\functions"

if (Test-Path $FunctionsPath) {
    Get-ChildItem -Path $FunctionsPath -Filter "*.ps1" | ForEach-Object { . $_.FullName }
    
    # Also load the logging function
    if (Test-Path "$FunctionsPath\Write-ToLog.ps1") {
        . "$FunctionsPath\Write-ToLog.ps1"
    }
}
else {
    Write-Host "Functions directory not found: $FunctionsPath" -ForegroundColor Red
    exit 1
}

Write-Host "Testing Winget-AutoUpdate Pinned Apps Functionality" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green

if ($TestGPO -or $All) {
    Write-Host "`nTesting GPO Pin Configuration..." -ForegroundColor Yellow
    
    # Test Get-PinnedApps function
    try {
        $gpoPins = Get-PinnedApps
        Write-Host "Get-PinnedApps executed successfully" -ForegroundColor Green
        Write-Host "Found $($gpoPins.Count) GPO-defined pins" -ForegroundColor Cyan
        
        foreach ($pin in $gpoPins) {
            Write-Host "  - $($pin.AppId) = $($pin.Version)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "Error testing Get-PinnedApps: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($TestWingetPins -or $All) {
    Write-Host "`nTesting Winget Pin Detection..." -ForegroundColor Yellow
    
    # Test Get-WingetPinnedApps function
    try {
        # First check if winget is available
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            $Script:Winget = $winget.Source
            $pinnedApps = Get-WingetPinnedApps
            Write-Host "Get-WingetPinnedApps executed successfully" -ForegroundColor Green
            Write-Host "Found $($pinnedApps.Count) currently pinned apps" -ForegroundColor Cyan
            
            foreach ($pin in $pinnedApps) {
                Write-Host "  - $($pin.AppId) = $($pin.Version)" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "Winget not found - skipping winget pin detection test" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Error testing Get-WingetPinnedApps: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($TestVersionPatterns -or $All) {
    Write-Host "`nTesting Version Pattern Matching..." -ForegroundColor Yellow
    
    # Test version pattern functions
    $testCases = @(
        @{ Current = "1.2.3"; Pinned = "1.2.3"; Expected = $true; Description = "Exact match" },
        @{ Current = "1.2.3"; Pinned = "1.2.*"; Expected = $true; Description = "Wildcard patch match" },
        @{ Current = "1.2.5"; Pinned = "1.2.*"; Expected = $true; Description = "Wildcard patch match (different patch)" },
        @{ Current = "1.3.0"; Pinned = "1.2.*"; Expected = $false; Description = "Wildcard patch no match" },
        @{ Current = "1.2.3"; Pinned = "1.*"; Expected = $true; Description = "Wildcard major match" },
        @{ Current = "2.0.0"; Pinned = "1.*"; Expected = $false; Description = "Wildcard major no match" }
    )
    
    try {
        foreach ($test in $testCases) {
            $result = Test-PinnedVersion -CurrentVersion $test.Current -PinnedVersion $test.Pinned
            $status = if ($result -eq $test.Expected) { "PASS" } else { "FAIL" }
            $color = if ($result -eq $test.Expected) { "Green" } else { "Red" }
            
            Write-Host "  $status - $($test.Description): '$($test.Current)' vs '$($test.Pinned)' = $result" -ForegroundColor $color
        }
        Write-Host "Version pattern testing completed" -ForegroundColor Green
    }
    catch {
        Write-Host "Error testing version patterns: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if (-not ($TestGPO -or $TestWingetPins -or $TestVersionPatterns -or $All)) {
    Write-Host "`nUsage: .\Test-PinnedApps.ps1 [-TestGPO] [-TestWingetPins] [-TestVersionPatterns] [-All]" -ForegroundColor Yellow
    Write-Host "  -TestGPO           Test GPO pin configuration reading" -ForegroundColor Gray
    Write-Host "  -TestWingetPins    Test winget pin detection" -ForegroundColor Gray
    Write-Host "  -TestVersionPatterns Test version pattern matching" -ForegroundColor Gray
    Write-Host "  -All               Run all tests" -ForegroundColor Gray
    Write-Host "`nExample: .\Test-PinnedApps.ps1 -All" -ForegroundColor Cyan
}

Write-Host "`nTesting completed!" -ForegroundColor Green
