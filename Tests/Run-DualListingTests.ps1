#!/usr/bin/env pwsh
<#
.SYNOPSIS
Test runner for Winget-AutoUpdate Dual Listing Mode

.DESCRIPTION
This script runs all the dual listing mode tests for Winget-AutoUpdate.
It includes unit tests, integration tests, and provides a comprehensive report.

.PARAMETER TestType
Specifies which type of tests to run. Options: All, Unit, Integration, Performance
Default: All

.PARAMETER OutputPath
Specifies the path to output test results. If not specified, results are shown on console only.

.PARAMETER SkipPrerequisiteCheck
Skips the check for required modules and dependencies.

.PARAMETER GenerateReport
Generates a detailed HTML report of test results.

.EXAMPLE
.\Run-DualListingTests.ps1

.EXAMPLE
.\Run-DualListingTests.ps1 -TestType Unit -OutputPath "C:\TestResults\dual-listing-tests.xml"

.EXAMPLE
.\Run-DualListingTests.ps1 -GenerateReport -OutputPath "C:\TestResults"
#>

param(
    [ValidateSet("All", "Unit", "Integration", "Performance")]
    [string]$TestType = "All",
    
    [string]$OutputPath = $null,
    
    [switch]$SkipPrerequisiteCheck,
    
    [switch]$GenerateReport
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Script constants
$SCRIPT_DIR = $PSScriptRoot
$SOURCES_DIR = Join-Path $SCRIPT_DIR "..\Sources"
$TESTS_DIR = Join-Path $SCRIPT_DIR ""

Write-Host "=== Winget-AutoUpdate Dual Listing Mode Test Runner ===" -ForegroundColor Cyan
Write-Host "Test Type: $TestType" -ForegroundColor White
Write-Host "Output Path: $(if ($OutputPath) { $OutputPath } else { "Console Only" })" -ForegroundColor White
Write-Host "Generate Report: $GenerateReport" -ForegroundColor White
Write-Host ""

# Check prerequisites
if (-not $SkipPrerequisiteCheck) {
    Write-Host "Checking prerequisites..." -ForegroundColor Yellow
    
    # Check if Pester is installed
    $pesterModule = Get-Module -Name Pester -ListAvailable
    if (-not $pesterModule) {
        Write-Host "Installing Pester module..." -ForegroundColor Yellow
        Install-Module -Name Pester -Force -SkipPublisherCheck
    }
    
    # Check if required source files exist
    $requiredFiles = @(
        "Winget-AutoUpdate\functions\Get-DualListApps.ps1",
        "Winget-AutoUpdate\functions\Get-IncludedApps.ps1",
        "Winget-AutoUpdate\functions\Get-ExcludedApps.ps1",
        "Winget-AutoUpdate\functions\Get-WAUConfig.ps1",
        "Winget-AutoUpdate\functions\Write-ToLog.ps1"
    )
    
    foreach ($file in $requiredFiles) {
        $fullPath = Join-Path $SOURCES_DIR $file
        if (-not (Test-Path $fullPath)) {
            Write-Error "Required file not found: $fullPath"
        }
    }
    
    Write-Host "Prerequisites check completed." -ForegroundColor Green
}

# Initialize test results
$testResults = @()
$startTime = Get-Date

try {
    # Run unit tests
    if ($TestType -eq "All" -or $TestType -eq "Unit") {
        Write-Host "Running unit tests..." -ForegroundColor Yellow
        
        $unitTestPath = Join-Path $TESTS_DIR "DualListingMode.Tests.ps1"
        if (Test-Path $unitTestPath) {
            $pesterConfig = @{
                Run = @{
                    Path = $unitTestPath
                    PassThru = $true
                }
                Output = @{
                    Verbosity = 'Detailed'
                }
            }
            
            if ($OutputPath) {
                $unitOutputPath = Join-Path $OutputPath "DualListingMode.Unit.Tests.xml"
                $pesterConfig.TestResult = @{
                    Enabled = $true
                    OutputPath = $unitOutputPath
                    OutputFormat = 'NUnitXml'
                }
            }
            
            $unitResults = Invoke-Pester -Configuration $pesterConfig
            $testResults += $unitResults
        }
        else {
            Write-Warning "Unit test file not found: $unitTestPath"
        }
    }
    
    # Run integration tests
    if ($TestType -eq "All" -or $TestType -eq "Integration") {
        Write-Host "Running integration tests..." -ForegroundColor Yellow
        
        $integrationTestPath = Join-Path $TESTS_DIR "DualListingMode.Integration.Tests.ps1"
        if (Test-Path $integrationTestPath) {
            $pesterConfig = @{
                Run = @{
                    Path = $integrationTestPath
                    PassThru = $true
                }
                Output = @{
                    Verbosity = 'Detailed'
                }
            }
            
            if ($OutputPath) {
                $integrationOutputPath = Join-Path $OutputPath "DualListingMode.Integration.Tests.xml"
                $pesterConfig.TestResult = @{
                    Enabled = $true
                    OutputPath = $integrationOutputPath
                    OutputFormat = 'NUnitXml'
                }
            }
            
            $integrationResults = Invoke-Pester -Configuration $pesterConfig
            $testResults += $integrationResults
        }
        else {
            Write-Warning "Integration test file not found: $integrationTestPath"
        }
    }
    
    # Run performance tests
    if ($TestType -eq "All" -or $TestType -eq "Performance") {
        Write-Host "Running performance tests..." -ForegroundColor Yellow
        
        # Performance tests are included in the main test suite
        # We can run them separately if needed
        Write-Host "Performance tests are included in the main test suite." -ForegroundColor Green
    }
    
    # Calculate summary
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    $totalTests = ($testResults | Measure-Object -Property TotalCount -Sum).Sum
    $passedTests = ($testResults | Measure-Object -Property PassedCount -Sum).Sum
    $failedTests = ($testResults | Measure-Object -Property FailedCount -Sum).Sum
    $skippedTests = ($testResults | Measure-Object -Property SkippedCount -Sum).Sum
    
    # Display summary
    Write-Host ""
    Write-Host "=== TEST SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Duration: $($duration.TotalSeconds) seconds" -ForegroundColor White
    Write-Host "Total Tests: $totalTests" -ForegroundColor White
    Write-Host "Passed: $passedTests" -ForegroundColor Green
    Write-Host "Failed: $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { "Red" } else { "Green" })
    Write-Host "Skipped: $skippedTests" -ForegroundColor Yellow
    Write-Host ""
    
    # Show failed tests
    if ($failedTests -gt 0) {
        Write-Host "FAILED TESTS:" -ForegroundColor Red
        foreach ($result in $testResults) {
            if ($result.FailedCount -gt 0) {
                $result.Failed | ForEach-Object {
                    Write-Host "  ❌ $($_.FullyQualifiedName)" -ForegroundColor Red
                    Write-Host "     $($_.ErrorRecord.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        Write-Host ""
    }
    
    # Generate HTML report if requested
    if ($GenerateReport) {
        Write-Host "Generating HTML report..." -ForegroundColor Yellow
        
        $reportPath = if ($OutputPath) { 
            Join-Path $OutputPath "DualListingMode.TestReport.html" 
        } else { 
            Join-Path $SCRIPT_DIR "DualListingMode.TestReport.html" 
        }
        
        $htmlReport = Generate-TestReport -TestResults $testResults -Duration $duration
        $htmlReport | Out-File -FilePath $reportPath -Encoding UTF8
        
        Write-Host "HTML report generated: $reportPath" -ForegroundColor Green
    }
    
    # Exit with appropriate code
    if ($failedTests -gt 0) {
        Write-Host "Tests failed! Exiting with code 1." -ForegroundColor Red
        exit 1
    }
    else {
        Write-Host "All tests passed! ✅" -ForegroundColor Green
        exit 0
    }
}
catch {
    Write-Error "Error running tests: $_"
    exit 1
}

function Generate-TestReport {
    param(
        [array]$TestResults,
        [TimeSpan]$Duration
    )
    
    $totalTests = ($TestResults | Measure-Object -Property TotalCount -Sum).Sum
    $passedTests = ($TestResults | Measure-Object -Property PassedCount -Sum).Sum
    $failedTests = ($TestResults | Measure-Object -Property FailedCount -Sum).Sum
    $skippedTests = ($TestResults | Measure-Object -Property SkippedCount -Sum).Sum
    
    $successRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 2) } else { 0 }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Winget-AutoUpdate Dual Listing Mode Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { display: flex; justify-content: space-around; margin: 20px 0; }
        .summary-item { text-align: center; padding: 10px; background-color: #f9f9f9; border-radius: 5px; }
        .success { color: #28a745; }
        .error { color: #dc3545; }
        .warning { color: #ffc107; }
        .test-group { margin: 20px 0; }
        .test-group h3 { background-color: #e9ecef; padding: 10px; margin: 0; }
        .test-item { padding: 10px; border-left: 4px solid #ccc; margin: 5px 0; }
        .test-passed { border-left-color: #28a745; background-color: #d4edda; }
        .test-failed { border-left-color: #dc3545; background-color: #f8d7da; }
        .test-skipped { border-left-color: #ffc107; background-color: #fff3cd; }
        .error-detail { font-size: 0.9em; color: #666; margin-top: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Winget-AutoUpdate Dual Listing Mode Test Report</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p>Duration: $($Duration.TotalSeconds) seconds</p>
    </div>
    
    <div class="summary">
        <div class="summary-item">
            <h3>Total Tests</h3>
            <p style="font-size: 2em; margin: 0;">$totalTests</p>
        </div>
        <div class="summary-item">
            <h3>Passed</h3>
            <p style="font-size: 2em; margin: 0; color: #28a745;">$passedTests</p>
        </div>
        <div class="summary-item">
            <h3>Failed</h3>
            <p style="font-size: 2em; margin: 0; color: #dc3545;">$failedTests</p>
        </div>
        <div class="summary-item">
            <h3>Skipped</h3>
            <p style="font-size: 2em; margin: 0; color: #ffc107;">$skippedTests</p>
        </div>
        <div class="summary-item">
            <h3>Success Rate</h3>
            <p style="font-size: 2em; margin: 0; color: $(if ($successRate -ge 80) { '#28a745' } else { '#dc3545' });">$successRate%</p>
        </div>
    </div>
    
    <div class="test-groups">
"@
    
    foreach ($result in $TestResults) {
        $html += @"
        <div class="test-group">
            <h3>$($result.Configuration.Run.Path)</h3>
"@
        
        foreach ($test in $result.Tests) {
            $cssClass = switch ($test.Result) {
                "Passed" { "test-passed" }
                "Failed" { "test-failed" }
                "Skipped" { "test-skipped" }
                default { "test-item" }
            }
            
            $html += @"
            <div class="test-item $cssClass">
                <strong>$($test.Name)</strong>
                <span class="$(if ($test.Result -eq 'Passed') { 'success' } elseif ($test.Result -eq 'Failed') { 'error' } else { 'warning' })">[$($test.Result)]</span>
"@
            
            if ($test.Result -eq "Failed" -and $test.ErrorRecord) {
                $html += @"
                <div class="error-detail">
                    <strong>Error:</strong> $($test.ErrorRecord.Exception.Message)
                </div>
"@
            }
            
            $html += "</div>"
        }
        
        $html += "</div>"
    }
    
    $html += @"
    </div>
    
    <div class="footer">
        <p><em>Generated by Winget-AutoUpdate Dual Listing Mode Test Runner</em></p>
    </div>
</body>
</html>
"@
    
    return $html
}
