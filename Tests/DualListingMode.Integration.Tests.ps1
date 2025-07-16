# Integration Tests for Dual Listing Mode Configuration Methods
# This test suite validates that dual listing mode works correctly across different configuration methods

BeforeAll {
    # Import required modules and functions
    . "$PSScriptRoot\DualListingMode.Helpers.ps1"
    . "$PSScriptRoot\..\Sources\Winget-AutoUpdate\functions\Get-WAUConfig.ps1"
    . "$PSScriptRoot\..\Sources\Winget-AutoUpdate\functions\Get-DualListApps.ps1"
    . "$PSScriptRoot\..\Sources\Winget-AutoUpdate\functions\Get-IncludedApps.ps1"
    . "$PSScriptRoot\..\Sources\Winget-AutoUpdate\functions\Get-ExcludedApps.ps1"
    . "$PSScriptRoot\..\Sources\Winget-AutoUpdate\functions\Write-ToLog.ps1"
    
    # Mock Write-ToLog to avoid logging during tests
    Mock Write-ToLog { }
    
    # Test apps for integration testing
    $script:IntegrationTestApps = @(
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
        }
    )
}

Describe "Dual Listing Mode - GPO Configuration" {
    
    Context "GPO-based dual listing configuration" {
        BeforeEach {
            # Mock GPO being enabled with dual listing
            Mock Get-ItemPropertyValue { 
                param($Path, $Name)
                if ($Name -eq "WAU_ActivateGPOManagement") { return 1 }
                return $null
            }
            
            Mock Get-ItemProperty { 
                param($Path)
                if ($Path -like "*Policies*") {
                    return [PSCustomObject]@{
                        WAU_ActivateGPOManagement = 1
                        WAU_UseDualListing = 1
                        WAU_UseWhiteList = 0
                        WAU_ListPath = "GPO"
                    }
                }
                return [PSCustomObject]@{
                    InstallLocation = "C:\Program Files\WAU"
                    ProductVersion = "1.20.0"
                }
            }
            
            # Mock GPO whitelist
            Mock Test-Path { 
                param($Path)
                if ($Path -eq "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList") { return $true }
                if ($Path -eq "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList") { return $true }
                return $false
            }
            
            Mock Get-Item { 
                param($Path)
                if ($Path -eq "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList") {
                    return [PSCustomObject]@{
                        Property = @("1", "2")
                    }
                }
                if ($Path -eq "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList") {
                    return [PSCustomObject]@{
                        Property = @("1", "2")
                    }
                }
                return $null
            }
            
            Mock Get-ItemPropertyValue { 
                param($Path, $Name)
                if ($Path -eq "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList") {
                    switch ($Name) {
                        "1" { return "Microsoft.PowerShell" }
                        "2" { return "Microsoft.VisualStudioCode" }
                    }
                }
                if ($Path -eq "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList") {
                    switch ($Name) {
                        "1" { return "Mozilla.Firefox" }
                        "2" { return "Google.Chrome" }
                    }
                }
                if ($Name -eq "WAU_ActivateGPOManagement") { return 1 }
                return $null
            }
            
            # Set global variables for GPO mode
            $script:GPOList = $true
            $script:URIList = $false
            $script:WorkingDir = "C:\Program Files\WAU"
        }
        
        It "Should detect dual listing mode from GPO" {
            $config = Get-WAUConfig
            $config.WAU_UseDualListing | Should -Be 1
        }
        
        It "Should load whitelist from GPO" {
            $includedApps = Get-IncludedApps
            $includedApps | Should -Contain "Microsoft.PowerShell"
            $includedApps | Should -Contain "Microsoft.VisualStudioCode"
        }
        
        It "Should load blacklist from GPO" {
            $excludedApps = Get-ExcludedApps
            $excludedApps | Should -Contain "Mozilla.Firefox"
            $excludedApps | Should -Contain "Google.Chrome"
        }
        
        It "Should process apps correctly with GPO dual listing" {
            $result = Get-DualListApps -OutdatedApps $script:IntegrationTestApps
            
            # PowerShell should be updated (in whitelist, not in blacklist)
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            
            # Firefox should be skipped (blacklist takes precedence)
            $firefoxResult = $result | Where-Object { $_.App.Id -eq "Mozilla.Firefox" }
            $firefoxResult.ShouldUpdate | Should -Be $false
            $firefoxResult.Reason | Should -Match "blacklist takes precedence"
        }
    }
    
    Context "GPO priority over other configurations" {
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
                        WAU_ActivateGPOManagement = 1
                        WAU_UseDualListing = 1
                        WAU_UseWhiteList = 0  # GPO says use dual listing
                    }
                }
                return [PSCustomObject]@{
                    InstallLocation = "C:\Program Files\WAU"
                    WAU_UseWhiteList = 1  # Local config says use whitelist
                    WAU_UseDualListing = 0  # Local config says don't use dual listing
                }
            }
        }
        
        It "Should prioritize GPO settings over local registry" {
            $config = Get-WAUConfig
            # GPO should override local settings
            $config.WAU_UseDualListing | Should -Be 1
            $config.WAU_UseWhiteList | Should -Be 0
        }
    }
}

Describe "Dual Listing Mode - Registry Configuration" {
    
    Context "Registry-based dual listing configuration" {
        BeforeEach {
            # Mock GPO being disabled
            Mock Get-ItemPropertyValue { 
                param($Path, $Name)
                if ($Name -eq "WAU_ActivateGPOManagement") { return 0 }
                return $null
            }
            
            Mock Get-ItemProperty { 
                param($Path)
                return [PSCustomObject]@{
                    InstallLocation = "C:\Program Files\WAU"
                    WAU_UseDualListing = 1
                    WAU_UseWhiteList = 0
                    ProductVersion = "1.20.0"
                }
            }
            
            # Mock file-based lists
            Mock Test-Path { 
                param($Path)
                if ($Path -eq "C:\Program Files\WAU\included_apps.txt") { return $true }
                if ($Path -eq "C:\Program Files\WAU\excluded_apps.txt") { return $true }
                return $false
            }
            
            Mock Get-Content { 
                param($Path)
                if ($Path -eq "C:\Program Files\WAU\included_apps.txt") {
                    return @("Microsoft.PowerShell", "Microsoft.VisualStudioCode")
                }
                if ($Path -eq "C:\Program Files\WAU\excluded_apps.txt") {
                    return @("Mozilla.Firefox", "Google.Chrome")
                }
                return @()
            }
            
            # Set global variables for local mode
            $script:GPOList = $false
            $script:URIList = $false
            $script:WorkingDir = "C:\Program Files\WAU"
        }
        
        It "Should detect dual listing mode from registry" {
            $config = Get-WAUConfig
            $config.WAU_UseDualListing | Should -Be 1
        }
        
        It "Should load whitelist from file when registry enables dual listing" {
            $includedApps = Get-IncludedApps
            $includedApps | Should -Contain "Microsoft.PowerShell"
            $includedApps | Should -Contain "Microsoft.VisualStudioCode"
        }
        
        It "Should load blacklist from file when registry enables dual listing" {
            $excludedApps = Get-ExcludedApps
            $excludedApps | Should -Contain "Mozilla.Firefox"
            $excludedApps | Should -Contain "Google.Chrome"
        }
        
        It "Should process apps correctly with registry dual listing" {
            $result = Get-DualListApps -OutdatedApps $script:IntegrationTestApps
            
            # PowerShell should be updated (in whitelist, not in blacklist)
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            
            # Firefox should be skipped (blacklist takes precedence)
            $firefoxResult = $result | Where-Object { $_.App.Id -eq "Mozilla.Firefox" }
            $firefoxResult.ShouldUpdate | Should -Be $false
            $firefoxResult.Reason | Should -Match "blacklist takes precedence"
        }
    }
}

Describe "Dual Listing Mode - File Configuration" {
    
    Context "File-based dual listing configuration" {
        BeforeEach {
            # Create temporary test directory
            $script:TestDir = New-Item -ItemType Directory -Path (Join-Path $TestDrive "WAU-FileTest") -Force
            $script:OriginalWorkingDir = $global:WorkingDir
            $global:WorkingDir = $script:TestDir.FullName
            
            # Create test files
            @("Microsoft.PowerShell", "Microsoft.VisualStudioCode") | Out-File -FilePath (Join-Path $script:TestDir "included_apps.txt") -Encoding UTF8
            @("Mozilla.Firefox", "Google.Chrome") | Out-File -FilePath (Join-Path $script:TestDir "excluded_apps.txt") -Encoding UTF8
            
            # Mock registry to enable dual listing
            Mock Get-ItemPropertyValue { 
                param($Path, $Name)
                if ($Name -eq "WAU_ActivateGPOManagement") { return 0 }
                return $null
            }
            
            Mock Get-ItemProperty { 
                param($Path)
                return [PSCustomObject]@{
                    InstallLocation = $script:TestDir.FullName
                    WAU_UseDualListing = 1
                    WAU_UseWhiteList = 0
                    ProductVersion = "1.20.0"
                }
            }
            
            # Set global variables for local mode
            $script:GPOList = $false
            $script:URIList = $false
        }
        
        AfterEach {
            $global:WorkingDir = $script:OriginalWorkingDir
        }
        
        It "Should load whitelist from file" {
            $script:WorkingDir = $script:TestDir.FullName
            $includedApps = Get-IncludedApps
            $includedApps | Should -Contain "Microsoft.PowerShell"
            $includedApps | Should -Contain "Microsoft.VisualStudioCode"
        }
        
        It "Should load blacklist from file" {
            $script:WorkingDir = $script:TestDir.FullName
            $excludedApps = Get-ExcludedApps
            $excludedApps | Should -Contain "Mozilla.Firefox"
            $excludedApps | Should -Contain "Google.Chrome"
        }
        
        It "Should process apps correctly with file-based dual listing" {
            $script:WorkingDir = $script:TestDir.FullName
            $result = Get-DualListApps -OutdatedApps $script:IntegrationTestApps
            
            # PowerShell should be updated (in whitelist, not in blacklist)
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            
            # Firefox should be skipped (blacklist takes precedence)
            $firefoxResult = $result | Where-Object { $_.App.Id -eq "Mozilla.Firefox" }
            $firefoxResult.ShouldUpdate | Should -Be $false
            $firefoxResult.Reason | Should -Match "blacklist takes precedence"
        }
        
        It "Should handle missing files gracefully" {
            $script:WorkingDir = $script:TestDir.FullName
            # Remove one of the files
            Remove-Item (Join-Path $script:TestDir "included_apps.txt") -Force
            
            $result = Get-DualListApps -OutdatedApps $script:IntegrationTestApps
            
            # Should not throw and should handle missing whitelist
            $result | Should -Not -BeNullOrEmpty
            
            # Apps not in blacklist should be updated when whitelist is missing
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            $powershellResult.Reason | Should -Match "not in blacklist and no whitelist configured"
        }
    }
}

Describe "Dual Listing Mode - URI Configuration" {
    
    Context "URI-based dual listing configuration" {
        BeforeEach {
            # Mock URI configuration
            Mock Get-ItemPropertyValue { 
                param($Path, $Name)
                if ($Name -eq "WAU_ActivateGPOManagement") { return 0 }
                return $null
            }
            
            Mock Get-ItemProperty { 
                param($Path)
                return [PSCustomObject]@{
                    InstallLocation = "C:\Program Files\WAU"
                    WAU_UseDualListing = 1
                    WAU_UseWhiteList = 0
                    WAU_ListPath = "https://example.com/apps.txt"
                    ProductVersion = "1.20.0"
                }
            }
            
            Mock Test-Path { 
                param($Path)
                if ($Path -eq "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate") { return $true }
                return $false
            }
            
            Mock Get-Item { 
                param($Path)
                if ($Path -eq "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate") {
                    # Return a mock registry key object
                    $mockKey = New-Object PSObject
                    $mockKey | Add-Member -MemberType ScriptMethod -Name GetValue -Value {
                        param($Name)
                        if ($Name -eq "WAU_URIList") { 
                            return "https://example.com/apps.txt" 
                        }
                        return $null
                    }
                    return $mockKey
                }
                return $null
            }
            
            Mock Invoke-WebRequest { 
                param($Uri)
                return [PSCustomObject]@{
                    BaseResponse = [PSCustomObject]@{
                        StatusCode = [System.Net.HttpStatusCode]::OK
                    }
                    Content = "Microsoft.PowerShell`r`nMicrosoft.VisualStudioCode"
                }
            }
            
            # Set global variables for URI mode
            $script:GPOList = $false
            $script:URIList = $true
            $script:WorkingDir = "C:\Program Files\WAU"
            $script:WAU_GPORoot = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
        }
        
        It "Should load apps from URI" {
            $includedApps = Get-IncludedApps
            $includedApps | Should -Contain "Microsoft.PowerShell"
            $includedApps | Should -Contain "Microsoft.VisualStudioCode"
        }
        
        It "Should handle URI failures gracefully" {
            Mock Invoke-WebRequest { 
                throw "Network error"
            }
            
            try {
                $includedApps = Get-IncludedApps
                $includedApps | Should -BeNullOrEmpty
            }
            catch {
                # The function should handle network errors gracefully
                $false | Should -Be $true -Because "Function should handle network errors gracefully"
            }
        }
    }
}

Describe "Dual Listing Mode - Configuration Priority" {
    
    Context "Configuration method priority" {
        It "Should prioritize GPO over Registry" {
            # GPO enabled with dual listing disabled
            Mock Get-ItemPropertyValue { 
                param($Path, $Name)
                if ($Name -eq "WAU_ActivateGPOManagement") { return 1 }
                return $null
            }
            
            Mock Get-ItemProperty { 
                param($Path)
                if ($Path -like "*Policies*") {
                    return [PSCustomObject]@{
                        WAU_UseDualListing = 0  # GPO says no dual listing
                    }
                }
                return [PSCustomObject]@{
                    InstallLocation = "C:\Program Files\WAU"
                    WAU_UseDualListing = 1  # Registry says dual listing
                    ProductVersion = "1.20.0"
                }
            }
            
            $config = Get-WAUConfig
            $config.WAU_UseDualListing | Should -Be 0  # GPO should win
        }
        
        It "Should use Registry when GPO is disabled" {
            # GPO disabled
            Mock Get-ItemPropertyValue { 
                param($Path, $Name)
                if ($Name -eq "WAU_ActivateGPOManagement") { return 0 }
                return $null
            }
            
            Mock Get-ItemProperty { 
                param($Path)
                return [PSCustomObject]@{
                    InstallLocation = "C:\Program Files\WAU"
                    WAU_UseDualListing = 1
                    ProductVersion = "1.20.0"
                }
            }
            
            $config = Get-WAUConfig
            $config.WAU_UseDualListing | Should -Be 1
        }
    }
}

Describe "Dual Listing Mode - Real World Scenarios" {
    
    Context "Enterprise deployment scenarios" {
        It "Should handle scenario: Allow most apps but block browsers on specific devices" {
            # Whitelist: Most common apps
            Mock Get-IncludedApps { 
                @(
                    "Microsoft.PowerShell",
                    "Microsoft.VisualStudioCode", 
                    "7zip.7zip",
                    "Git.Git",
                    "Microsoft.Teams",
                    "Adobe.Acrobat.Reader.64-bit"
                )
            }
            
            # Blacklist: Browsers (for specific device group)
            Mock Get-ExcludedApps { 
                @(
                    "Mozilla.Firefox",
                    "Google.Chrome",
                    "Microsoft.Edge"
                )
            }
            
            $result = Get-DualListApps -OutdatedApps $script:IntegrationTestApps
            
            # PowerShell should be updated (in whitelist, not in blacklist)
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            
            # Firefox should be blocked (blacklist takes precedence)
            $firefoxResult = $result | Where-Object { $_.App.Id -eq "Mozilla.Firefox" }
            $firefoxResult.ShouldUpdate | Should -Be $false
            $firefoxResult.Reason | Should -Match "blacklist takes precedence"
        }
        
        It "Should handle scenario: Block security-sensitive apps except on admin devices" {
            # Whitelist: All apps for admin devices
            Mock Get-IncludedApps { 
                @(
                    "Microsoft.*",
                    "Adobe.*",
                    "TeamViewer.*"
                )
            }
            
            # Blacklist: Security-sensitive apps
            Mock Get-ExcludedApps { 
                @(
                    "TeamViewer.TeamViewer"  # Blocked by default, but allowed for admins via whitelist
                )
            }
            
            $testApps = @(
                [PSCustomObject]@{
                    Id = "Microsoft.PowerShell"
                    Name = "PowerShell"
                    Version = "7.3.0"
                    AvailableVersion = "7.3.1"
                },
                [PSCustomObject]@{
                    Id = "TeamViewer.TeamViewer"
                    Name = "TeamViewer"
                    Version = "15.0.0"
                    AvailableVersion = "15.0.1"
                }
            )
            
            $result = Get-DualListApps -OutdatedApps $testApps
            
            # PowerShell should be updated (matches whitelist wildcard)
            $powershellResult = $result | Where-Object { $_.App.Id -eq "Microsoft.PowerShell" }
            $powershellResult.ShouldUpdate | Should -Be $true
            
            # TeamViewer should be blocked (blacklist takes precedence over whitelist)
            $teamviewerResult = $result | Where-Object { $_.App.Id -eq "TeamViewer.TeamViewer" }
            $teamviewerResult.ShouldUpdate | Should -Be $false
            $teamviewerResult.Reason | Should -Match "blacklist takes precedence"
        }
    }
}

Describe "Dual Listing Mode - Error Handling" {
    
    Context "Error scenarios" {
        It "Should handle corrupted configuration gracefully" {
            Mock Get-ItemPropertyValue { throw "Registry error" }
            Mock Get-ItemProperty { throw "Registry error" }
            
            try {
                $config = Get-WAUConfig
                # If we get here, the function handled the error gracefully
                $true | Should -Be $true
            }
            catch {
                # If an exception is thrown, the function didn't handle it gracefully
                $false | Should -Be $true -Because "Function should handle registry errors gracefully"
            }
        }
        
        It "Should handle missing files gracefully" {
            Mock Get-IncludedApps { throw "File not found" }
            Mock Get-ExcludedApps { @() }
            
            try {
                $result = Get-DualListApps -OutdatedApps $script:IntegrationTestApps
                # If we get here, the function handled the error gracefully
                $true | Should -Be $true
            }
            catch {
                # If an exception is thrown, the function didn't handle it gracefully
                $false | Should -Be $true -Because "Function should handle file errors gracefully"
            }
        }
        
        It "Should handle empty app lists" {
            Mock Get-IncludedApps { @() }
            Mock Get-ExcludedApps { @() }
            
            $result = Get-DualListApps -OutdatedApps $script:IntegrationTestApps
            
            # All apps should be updated when both lists are empty
            $validApps = $result | Where-Object { $_.App.Version -ne "Unknown" }
            $validApps | ForEach-Object { $_.ShouldUpdate | Should -Be $true }
        }
    }
}
