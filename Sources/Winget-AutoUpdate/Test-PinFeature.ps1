<#
.SYNOPSIS
    Test script for WAU Pin Feature
.DESCRIPTION
    This script tests the basic functionality of the WAU Pin feature
    to ensure all components are working correctly.
#>

# Get the Working Dir
[string]$Script:WorkingDir = $PSScriptRoot;

# Get Functions
Get-ChildItem -Path "$($Script:WorkingDir)\functions" -File -Filter "*.ps1" -Depth 0 | ForEach-Object { . $_.FullName; }

# Initialize logging
Initialize-WAULogging -LogFileName "test-pin-feature.log"

# Get Winget command
[string]$Script:Winget = Get-WingetCmd;

Write-Host "WAU Pin Feature Test" -ForegroundColor Cyan
Write-Host "===================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check if Winget is available
Write-Host "Test 1: Checking Winget availability..." -ForegroundColor Yellow
if ($Script:Winget) {
    Write-Host "[+] Winget found: $Script:Winget" -ForegroundColor Green
} else {
    Write-Host "[-] Winget not found" -ForegroundColor Red
    exit 1
}

# Test 2: Check pin support
Write-Host "Test 2: Checking Winget pin support..." -ForegroundColor Yellow
$pinSupported = Test-WingetPinSupport
if ($pinSupported) {
    Write-Host "[+] Winget pin support available" -ForegroundColor Green
} else {
    Write-Host "[-] Winget pin support not available" -ForegroundColor Red
    exit 1
}

# Test 3: Test getting current pins
Write-Host "Test 3: Testing Get-WingetPinnedApps function..." -ForegroundColor Yellow
try {
    $currentPins = Get-WingetPinnedApps | Where-Object { $_.Id }
    Write-Host "[+] Successfully retrieved current pins ($($currentPins.Count) found)" -ForegroundColor Green
} catch {
    Write-Host "[-] Failed to get current pins: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Test pin configuration loading
Write-Host "Test 4: Testing pin configuration loading..." -ForegroundColor Yellow
try {
    # Create a temporary WAUConfig for testing
    $Script:WAUConfig = @{
        WAU_ActivateGPOManagement = 0
        WAU_PinnedAppsPath = $null
        WAU_EnablePinManagement = 1 # Enable for testing
    }
    
    $pinConfigs = Get-WAUPinConfig | Where-Object { $_.Id }
    Write-Host "[+] Successfully loaded pin configurations ($($pinConfigs.Count) found)" -ForegroundColor Green
    
    if ($pinConfigs.Count -gt 0) {
        Write-Host "  Pin configurations found:" -ForegroundColor Gray
        foreach ($config in $pinConfigs) {
            Write-Host "    - $($config.Id) = $($config.Version) (Source: $($config.Source))" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "[-] Failed to load pin configurations: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 5: Test pin configuration file format
Write-Host "Test 5: Testing pin configuration file format..." -ForegroundColor Yellow
$testConfigFile = Join-Path $WorkingDir "pinned_apps.txt"
if (Test-Path $testConfigFile) {
    try {
        $content = Get-Content $testConfigFile -ErrorAction Stop
        $validLines = 0
        $invalidLines = 0
        
        foreach ($line in $content) {
            $line = $line.Trim()
            if ($line -and !$line.StartsWith("#")) {
                if ($line.Contains("=")) {
                    $parts = $line.Split("=", 2)
                    if ($parts.Length -eq 2 -and $parts[0].Trim() -and $parts[1].Trim()) {
                        $validLines++
                    } else {
                        $invalidLines++
                    }
                } else {
                    $invalidLines++
                }
            }
        }
        
if ($invalidLines -eq 0) {
            Write-Host "[+] Pin configuration file format is valid ($validLines valid entries)" -ForegroundColor Green
        } else {
            Write-Host "[!] Pin configuration file has $invalidLines invalid lines" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[-] Failed to read pin configuration file: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "[i] No local pin configuration file found (this is normal)" -ForegroundColor Gray
}

# Test 6: Test a safe pin operation (if no critical pins exist)
Write-Host "Test 6: Testing pin add/remove operations..." -ForegroundColor Yellow
$testAppId = "Microsoft.WindowsCalculator"  # Safe app to test with

try {
    # Check if app is installed
    $appInstalled = & $Winget list --id $testAppId --exact 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Testing pin add..." -ForegroundColor Gray
        $addResult = Set-WingetPin -Id $testAppId -Action "Add"
        
if ($addResult) {
            Write-Host "  [+] Pin add successful" -ForegroundColor Green
            
            # Verify pin was added
            $pinsAfterAdd = Get-WingetPinnedApps
            $pinFound = $pinsAfterAdd | Where-Object { $_.Id -eq $testAppId }
            
            if ($pinFound) {
                Write-Host "  [+] Pin verified in pin list" -ForegroundColor Green
                
                # Remove the test pin
                Write-Host "  Testing pin remove..." -ForegroundColor Gray
                $removeResult = Set-WingetPin -Id $testAppId -Action "Remove"
                
                if ($removeResult) {
                    Write-Host "  [+] Pin remove successful" -ForegroundColor Green
                    Write-Host "[+] Pin add/remove operations working correctly" -ForegroundColor Green
                } else {
                    Write-Host "  [-] Pin remove failed" -ForegroundColor Red
                }
            } else {
                Write-Host "  [-] Pin not found in pin list after adding" -ForegroundColor Red
            }
        } else {
            Write-Host "  [-] Pin add failed" -ForegroundColor Red
        }
    } else {
        Write-Host "[i] Test app ($testAppId) not installed - skipping pin operation test" -ForegroundColor Gray
    }
} catch {
    Write-Host "[-] Pin operation test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Pin feature test completed!" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "1. Configure pin settings in pinned_apps.txt or via GPO" -ForegroundColor Gray
Write-Host "2. Run WAU to see pins in action" -ForegroundColor Gray
Write-Host "3. Use WAU-PinManager.ps1 for ongoing pin management" -ForegroundColor Gray
Write-Host "4. Check WAU logs for pin-related messages" -ForegroundColor Gray
