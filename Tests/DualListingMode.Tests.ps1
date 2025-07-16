# Winget-AutoUpdate Dual Listing Mode Tests
# This test suite validates the dual listing mode functionality that allows
# using both whitelist and blacklist configurations simultaneously

BeforeAll {
    # Import the necessary functions
    . "$PSScriptRoot\..\Sources\Winget-AutoUpdate\functions\Get-DualListApps.ps1"
    . "$PSScriptRoot\..\Sources\Winget-AutoUpdate\functions\Get-IncludedApps.ps1"
    . "$PSScriptRoot\..\Sources\Winget-AutoUpdate\functions\Get-ExcludedApps.ps1"
    . "$PSScriptRoot\..\Sources\Winget-AutoUpdate\functions\Write-ToLog.ps1"
    . "$PSScriptRoot\..\Sources\Winget-AutoUpdate\functions\Get-WAUConfig.ps1"
    
    # Mock Write-ToLog function to avoid logging during tests
    Mock Write-ToLog { }
    
    # Sample test data
    $script:TestApps = @(
        [PSCustomObject]@{
            Id = "Microsoft.PowerShell"
            Name = "PowerShell"
            Version = "7.3.0"
            AvailableVersion = "7.3.1"
        },
        [PSCustomObject]@{
            Id = "Microsoft.VisualStudioCode"
            Name = "Visual Studio Code"
            Version = "1.85.0"
            AvailableVersion = "1.85.1"
        },
        [PSCustomObject]@{
            Id = "Mozilla.Firefox"
            Name = "Firefox"
            Version = "119.0"
            AvailableVersion = "120.0"
        },
        [PSCustomObject]@{
            Id = "Google.Chrome"
            Name = "Chrome"
            Version = "118.0"
            AvailableVersion = "119.0"
        },
        [PSCustomObject]@{
            Id = "Microsoft.Teams"
            Name = "Teams"
            Version = "1.5.0"
            AvailableVersion = "1.6.0"
        },
        [PSCustomObject]@{
            Id = "SomeApp.UnknownVersion"
            Name = "Unknown Version App"
            Version = "Unknown"
            AvailableVersion = "1.0.0"
        }
    )
}

Describe "Dual Listing Mode Core Functionality" {
    
    Context "When only whitelist is configured" {
        BeforeEach {
            Mock Get-IncludedApps { @("Microsoft.PowerShell", "Microsoft.VisualStudioCode") }
            Mock Get-ExcludedApps { @() }
        }
        
        It "Should update apps that are in the whitelist" {
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            $powershellResult.Reason | Should -Match "whitelist"
            
            $vscodeResult = $result | Where-Object { $_.App.Id -eq "Microsoft.VisualStudioCode" }
            $vscodeResult.ShouldUpdate | Should -Be $true
            $vscodeResult.Reason | Should -Match "whitelist"
        }
        
        It "Should skip apps that are not in the whitelist" {
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            $firefoxResult = $result | Where-Object { $_.App.Id -eq "Mozilla.Firefox" }
            $firefoxResult.ShouldUpdate | Should -Be $false
            $firefoxResult.Reason | Should -Match "not in the included app list"
        }
    }
    
    Context "When only blacklist is configured" {
        BeforeEach {
            Mock Get-IncludedApps { @() }
            Mock Get-ExcludedApps { @("Mozilla.Firefox", "Google.Chrome") }
        }
        
        It "Should skip apps that are in the blacklist" {
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            $firefoxResult = $result | Where-Object { $_.App.Id -eq "Mozilla.Firefox" }
            $firefoxResult.ShouldUpdate | Should -Be $false
            $firefoxResult.Reason | Should -Match "excluded app list"
            
            $chromeResult = $result | Where-Object { $_.App.Id -eq "Google.Chrome" }
            $chromeResult.ShouldUpdate | Should -Be $false
            $chromeResult.Reason | Should -Match "excluded app list"
        }
        
        It "Should update apps that are not in the blacklist" {
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            $powershellResult.Reason | Should -Match "not in blacklist and no whitelist configured"
        }
    }
    
    Context "When both whitelist and blacklist are configured" {
        BeforeEach {
            Mock Get-IncludedApps { @("Microsoft.PowerShell", "Microsoft.VisualStudioCode", "Mozilla.Firefox") }
            Mock Get-ExcludedApps { @("Mozilla.Firefox", "Google.Chrome") }
        }
        
        It "Should respect blacklist over whitelist (blacklist takes precedence)" {
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            # Firefox is in both whitelist and blacklist - should be skipped due to blacklist precedence
            $firefoxResult = $result | Where-Object { $_.App.Id -eq "Mozilla.Firefox" }
            $firefoxResult.ShouldUpdate | Should -Be $false
            $firefoxResult.Reason | Should -Match "blacklist takes precedence"
        }
        
        It "Should update apps that are in whitelist but not in blacklist" {
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            $powershellResult.Reason | Should -Match "whitelist"
            
            $vscodeResult = $result | Where-Object { $_.App.Id -eq "Microsoft.VisualStudioCode" }
            $vscodeResult.ShouldUpdate | Should -Be $true
            $vscodeResult.Reason | Should -Match "whitelist"
        }
        
        It "Should skip apps that are not in whitelist and not in blacklist" {
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            $teamsResult = $result | Where-Object { $_.App.Id -eq "Microsoft.Teams" }
            $teamsResult.ShouldUpdate | Should -Be $false
            $teamsResult.Reason | Should -Match "not in the included app list"
        }
    }
    
    Context "When wildcards are used" {
        BeforeEach {
            Mock Get-IncludedApps { @("Microsoft.*", "Mozilla.Firefox") }
            Mock Get-ExcludedApps { @("Microsoft.Teams*") }
        }
        
        It "Should handle wildcard patterns in whitelist" {
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            $powershellResult.Reason | Should -Match "matches.*wildcard.*whitelist"
        }
        
        It "Should handle wildcard patterns in blacklist with precedence" {
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            $teamsResult = $result | Where-Object { $_.App.Id -eq "Microsoft.Teams" }
            $teamsResult.ShouldUpdate | Should -Be $false
            $teamsResult.Reason | Should -Match "matches.*wildcard.*excluded app list.*blacklist takes precedence"
        }
    }
    
    Context "When apps have unknown versions" {
        BeforeEach {
            Mock Get-IncludedApps { @("SomeApp.UnknownVersion") }
            Mock Get-ExcludedApps { @() }
        }
        
        It "Should skip apps with unknown versions regardless of lists" {
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            $unknownResult = $result | Where-Object { $_.App.Id -eq "SomeApp.UnknownVersion" }
            $unknownResult.ShouldUpdate | Should -Be $false
            $unknownResult.Reason | Should -Match "Unknown"
        }
    }
}

Describe "Dual Listing Mode Configuration" {
    
    Context "Registry Configuration" {
        BeforeEach {
            # Mock registry access
            Mock Get-ItemProperty { 
                [PSCustomObject]@{
                    WAU_UseDualListing = 1
                    WAU_UseWhiteList = 0
                    InstallLocation = "C:\Program Files\WAU"
                } 
            }
            Mock Get-ItemPropertyValue { 
                param($Path, $Name)
                if ($Name -eq "WAU_ActivateGPOManagement") { return 0 }
                return $null
            }
        }
        
        It "Should detect dual listing mode from registry" {
            $config = Get-WAUConfig
            $config.WAU_UseDualListing | Should -Be 1
        }
    }
    
    Context "GPO Configuration" {
        BeforeEach {
            # Mock GPO being enabled
            Mock Get-ItemPropertyValue { 
                param($Path, $Name)
                if ($Name -eq "WAU_ActivateGPOManagement") { return 1 }
                return $null
            }
            Mock Get-ItemProperty { 
                param($Path)
                if ($Path -like "*Policies*") {
                    return [PSCustomObject]@{
                        WAU_UseDualListing = 1
                        WAU_UseWhiteList = 0
                    }
                }
                return [PSCustomObject]@{
                    InstallLocation = "C:\Program Files\WAU"
                }
            }
        }
        
        It "Should detect dual listing mode from GPO" {
            $config = Get-WAUConfig
            $config.WAU_UseDualListing | Should -Be 1
        }
    }
    
    Context "File-based Configuration" {
        BeforeEach {
            # Create temporary test files
            $script:TestWorkingDir = New-Item -ItemType Directory -Path (Join-Path $TestDrive "WAU") -Force
            $script:OriginalWorkingDir = $global:WorkingDir
            $global:WorkingDir = $script:TestWorkingDir.FullName
            
            # Create test files
            "Microsoft.PowerShell" | Out-File -FilePath (Join-Path $script:TestWorkingDir "included_apps.txt")
            "Mozilla.Firefox" | Out-File -FilePath (Join-Path $script:TestWorkingDir "excluded_apps.txt")
            
            Mock Get-ItemProperty { 
                [PSCustomObject]@{
                    WAU_UseDualListing = 1
                    InstallLocation = $script:TestWorkingDir.FullName
                } 
            }
            Mock Get-ItemPropertyValue { return $null }
        }
        
        AfterEach {
            $global:WorkingDir = $script:OriginalWorkingDir
        }
        
        It "Should read whitelist from file when dual listing is enabled" {
            $script:GPOList = $false
            $script:URIList = $false
            
            $includedApps = Get-IncludedApps
            $includedApps | Should -Contain "Microsoft.PowerShell"
        }
        
        It "Should read blacklist from file when dual listing is enabled" {
            $script:GPOList = $false
            $script:URIList = $false
            
            $excludedApps = Get-ExcludedApps
            $excludedApps | Should -Contain "Mozilla.Firefox"
        }
    }
}

Describe "Dual Listing Mode Integration" {
    
    Context "Integration with Winget-Upgrade.ps1" {
        BeforeEach {
            # Mock configuration that enables dual listing
            Mock Get-WAUConfig { 
                [PSCustomObject]@{
                    WAU_UseDualListing = 1
                    WAU_UseWhiteList = 0
                    InstallLocation = "C:\Program Files\WAU"
                } 
            }
            
            # Mock app lists
            Mock Get-IncludedApps { @("Microsoft.PowerShell") }
            Mock Get-ExcludedApps { @("Mozilla.Firefox") }
        }
        
        It "Should set UseDualListing flag when WAU_UseDualListing is 1" {
            $WAUConfig = Get-WAUConfig
            $WAUConfig.WAU_UseDualListing | Should -Be 1
            
            # This simulates the logic in Winget-Upgrade.ps1
            $UseDualListing = $WAUConfig.WAU_UseDualListing -eq 1
            $UseDualListing | Should -Be $true
        }
        
        It "Should prioritize dual listing over whitelist mode" {
            $WAUConfig = Get-WAUConfig
            
            # This simulates the logic in Winget-Upgrade.ps1
            if ($WAUConfig.WAU_UseDualListing -eq 1) {
                $UseDualListing = $true
                $UseWhiteList = $false
            } elseif ($WAUConfig.WAU_UseWhiteList -eq 1) {
                $UseWhiteList = $true
                $UseDualListing = $false
            }
            
            $UseDualListing | Should -Be $true
            $UseWhiteList | Should -Be $false
        }
    }
}

Describe "Dual Listing Mode Edge Cases" {
    
    Context "Empty Lists" {
        It "Should handle empty whitelist gracefully" {
            Mock Get-IncludedApps { @() }
            Mock Get-ExcludedApps { @("Mozilla.Firefox") }
            
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            # Apps not in blacklist should be updated when whitelist is empty
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            $powershellResult.Reason | Should -Match "not in blacklist and no whitelist configured"
        }
        
        It "Should handle empty blacklist gracefully" {
            Mock Get-IncludedApps { @("Microsoft.PowerShell") }
            Mock Get-ExcludedApps { @() }
            
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            # Apps in whitelist should be updated when blacklist is empty
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            $powershellResult.Reason | Should -Match "whitelist"
        }
        
        It "Should handle both lists being empty" {
            Mock Get-IncludedApps { @() }
            Mock Get-ExcludedApps { @() }
            
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            # All apps should be updated when both lists are empty
            $results = $result | Where-Object { $_.App.Version -ne "Unknown" }
            $results | ForEach-Object { $_.ShouldUpdate | Should -Be $true }
        }
    }
    
    Context "Null Lists" {
        It "Should handle null whitelist" {
            Mock Get-IncludedApps { $null }
            Mock Get-ExcludedApps { @("Mozilla.Firefox") }
            
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            # Should not throw and should treat as empty whitelist
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle null blacklist" {
            Mock Get-IncludedApps { @("Microsoft.PowerShell") }
            Mock Get-ExcludedApps { $null }
            
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            # Should not throw and should treat as empty blacklist
            $result | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Case Sensitivity" {
        BeforeEach {
            Mock Get-IncludedApps { @("microsoft.powershell") }  # lowercase
            Mock Get-ExcludedApps { @("MOZILLA.FIREFOX") }       # uppercase
        }
        
        It "Should handle case-insensitive matching properly" {
            $result = Get-DualListApps -OutdatedApps $script:TestApps
            
            # PowerShell should match despite case difference
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            
            # Firefox should match despite case difference
            $firefoxResult = $result | Where-Object { $_.App.Id -eq "Mozilla.Firefox" }
            $firefoxResult.ShouldUpdate | Should -Be $false
        }
    }
}

Describe "Dual Listing Mode Performance" {
    
    Context "Large App Lists" {
        BeforeEach {
            # Create a large list of test apps
            $script:LargeAppList = 1..1000 | ForEach-Object {
                [PSCustomObject]@{
                    Id = "TestApp$_"
                    Name = "Test App $_"
                    Version = "1.0.0"
                    AvailableVersion = "1.0.1"
                }
            }
            
            Mock Get-IncludedApps { @("TestApp1", "TestApp500", "TestApp1000") }
            Mock Get-ExcludedApps { @("TestApp2", "TestApp501") }
        }
        
        It "Should handle large app lists efficiently" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-DualListApps -OutdatedApps $script:LargeAppList
            $stopwatch.Stop()
            
            # Should complete within reasonable time (adjust threshold as needed)
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
            
            # Should return correct number of results
            $result.Count | Should -Be 1000
        }
    }
}
