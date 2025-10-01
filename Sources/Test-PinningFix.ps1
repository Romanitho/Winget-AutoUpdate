# Test script to verify the pinning fix for version mismatch issue
# This script tests the Get-WingetPinnedApps parsing and the Sync-WingetPins clean/reset approach

#region Setup
$Script:WorkingDir = Split-Path -Parent $PSScriptRoot
$FunctionsDir = Join-Path $Script:WorkingDir "Winget-AutoUpdate\functions"

# Load required functions
. (Join-Path $FunctionsDir "Write-ToLog.ps1")
. (Join-Path $FunctionsDir "Get-WingetCmd.ps1")
. (Join-Path $FunctionsDir "Get-WingetPinnedApps.ps1")
. (Join-Path $FunctionsDir "Set-WingetPin.ps1")

# Initialize log
$Script:LogFile = Join-Path $Script:WorkingDir "Winget-AutoUpdate\logs\test-pinning.log"
if (Test-Path $Script:LogFile) {
    Remove-Item $Script:LogFile -Force
}

Write-ToLog "=== Testing Pinning Fix ===" "Cyan"
#endregion Setup

#region Get Winget
Write-ToLog "Getting winget command..." "Gray"
$Script:Winget = Get-WingetCmd
if (-not $Script:Winget) {
    Write-ToLog "ERROR: Winget not found!" "Red"
    exit 1
}
Write-ToLog "Winget found at: $Script:Winget" "Green"
#endregion Get Winget

#region Test 1: Get Current Pins
Write-ToLog "`n--- Test 1: Get Current Pinned Apps ---" "Yellow"
$currentPins = Get-WingetPinnedApps
if ($currentPins) {
    Write-ToLog "Found $($currentPins.Count) currently pinned app(s):" "Green"
    foreach ($pin in $currentPins) {
        Write-ToLog "  - AppId: $($pin.AppId), Pinned Version: $($pin.Version)" "Gray"
    }
}
else {
    Write-ToLog "No apps currently pinned" "Gray"
}
#endregion Test 1

#region Test 2: Simulate GPO Pins
Write-ToLog "`n--- Test 2: Simulate GPO Pin Configuration ---" "Yellow"

# Create mock GPO pins (adjust these to match apps you have installed)
$mockGpoPins = @(
    [PSCustomObject]@{
        AppId = "Microsoft.PowerToys"
        Version = "0.75.0"
    },
    [PSCustomObject]@{
        AppId = "VideoLAN.VLC"
        Version = "3.0.18"
    }
)

Write-ToLog "Mock GPO pins created:" "Green"
foreach ($pin in $mockGpoPins) {
    Write-ToLog "  - AppId: $($pin.AppId), Version: $($pin.Version)" "Gray"
}
#endregion Test 2

#region Test 3: Test Sync-WingetPins (Clean and Reset)
Write-ToLog "`n--- Test 3: Test Sync-WingetPins (Clean and Reset Approach) ---" "Yellow"
Write-ToLog "NOTE: This will remove all current pins and apply the mock GPO pins" "Yellow"
Write-ToLog "Press Ctrl+C within 5 seconds to cancel..." "Yellow"
Start-Sleep -Seconds 5

$syncResult = Sync-WingetPins -DesiredPins $mockGpoPins -Source "winget"
if ($syncResult) {
    Write-ToLog "Pin synchronization completed successfully" "Green"
}
else {
    Write-ToLog "Pin synchronization failed" "Red"
}
#endregion Test 3

#region Test 4: Verify Pins After Sync
Write-ToLog "`n--- Test 4: Verify Pins After Synchronization ---" "Yellow"
$pinsAfterSync = Get-WingetPinnedApps
if ($pinsAfterSync) {
    Write-ToLog "Found $($pinsAfterSync.Count) pinned app(s) after sync:" "Green"
    foreach ($pin in $pinsAfterSync) {
        Write-ToLog "  - AppId: $($pin.AppId), Pinned Version: $($pin.Version)" "Gray"
        
        # Check if this matches our mock GPO pins
        $matchingGpoPin = $mockGpoPins | Where-Object { $_.AppId -eq $pin.AppId }
        if ($matchingGpoPin) {
            if ($pin.Version -eq $matchingGpoPin.Version) {
                Write-ToLog "    ✓ Version matches GPO configuration" "Green"
            }
            else {
                Write-ToLog "    ✗ Version mismatch! Expected: $($matchingGpoPin.Version), Got: $($pin.Version)" "Red"
            }
        }
    }
}
else {
    Write-ToLog "No apps pinned after sync" "Yellow"
}
#endregion Test 4

#region Test 5: Re-run Sync (Should remove and re-add all pins)
Write-ToLog "`n--- Test 5: Re-run Sync to Verify Clean/Reset Works ---" "Yellow"
$syncResult2 = Sync-WingetPins -DesiredPins $mockGpoPins -Source "winget"
if ($syncResult2) {
    Write-ToLog "Second pin synchronization completed successfully" "Green"
}
else {
    Write-ToLog "Second pin synchronization failed" "Red"
}

$pinsAfterSecondSync = Get-WingetPinnedApps
Write-ToLog "Pins after second sync: $($pinsAfterSecondSync.Count)" "Gray"
#endregion Test 5

#region Cleanup Prompt
Write-ToLog "`n=== Test Complete ===" "Cyan"
Write-ToLog "Log file location: $Script:LogFile" "Gray"
Write-ToLog "`nDo you want to clean up the test pins? (Y/N)" "Yellow"
$cleanup = Read-Host
if ($cleanup -eq "Y" -or $cleanup -eq "y") {
    Write-ToLog "Cleaning up test pins..." "Yellow"
    foreach ($pin in $pinsAfterSecondSync) {
        Remove-WingetPin -AppId $pin.AppId -Source "winget"
    }
    Write-ToLog "Cleanup complete" "Green"
}
else {
    Write-ToLog "Skipping cleanup - pins remain in place" "Gray"
}
#endregion Cleanup Prompt
