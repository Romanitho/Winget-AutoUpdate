# Dual Listing Mode Feature Documentation

## Overview

The Dual Listing Mode feature allows Winget-AutoUpdate (WAU) to use both whitelist and blacklist simultaneously, providing more flexible application management in enterprise environments.

## Key Principles

1. **Blacklist Precedence**: When an application appears in both whitelist and blacklist, the blacklist always takes precedence
2. **Default Behavior**: Applications not in either list follow the default WAU behavior
3. **Configuration Flexibility**: Can be configured via GPO, registry, or files

## Implementation Details

### Core Functions

#### `Get-DualListApps.ps1`
- **Purpose**: Main logic for dual listing mode
- **Input**: Array of outdated applications
- **Output**: Array of applications with update decisions
- **Key Logic**:
  - Loads whitelist and blacklist
  - Applies blacklist precedence rule
  - Handles unknown versions gracefully
  - Supports wildcard matching

#### `Get-WAUConfig.ps1` (Enhanced)
- **Purpose**: Configuration management with dual listing support
- **Features**:
  - GPO precedence handling
  - Registry fallback
  - File-based configuration
  - Error handling with graceful fallbacks

#### `Get-IncludedApps.ps1` (Enhanced)
- **Purpose**: Loads whitelist from various sources
- **Features**:
  - GPO registry support
  - File-based lists
  - URI-based lists
  - Error handling

#### `Get-ExcludedApps.ps1` (Enhanced)
- **Purpose**: Loads blacklist from various sources
- **Features**:
  - GPO registry support
  - File-based lists
  - Error handling

### Configuration Methods

#### 1. Group Policy (GPO) - Recommended for Enterprise
```
Registry Path: HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate
Values:
- WAU_UseDualListing = 1 (DWORD)
- WAU_ActivateGPOManagement = 1 (DWORD)

Whitelist: HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList
Blacklist: HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList
```

#### 2. Registry Configuration
```
Registry Path: HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate
Values:
- WAU_UseDualListing = 1 (DWORD)
```

#### 3. File-based Configuration
```
Files:
- included_apps.txt (whitelist)
- excluded_apps.txt (blacklist)
```

### MSI Installation Support

The MSI installer (`build.wxs`) includes:
- Registry value creation for `WAU_UseDualListing`
- Automatic configuration during installation
- Upgrade-safe settings

### Decision Logic Flow

```
1. Check if dual listing mode is enabled
2. If disabled: Use standard WAU behavior
3. If enabled:
   a. Load whitelist and blacklist
   b. For each outdated app:
      - If in blacklist: BLOCK (regardless of whitelist)
      - If in whitelist (and not blacklist): ALLOW
      - If in neither: Use default WAU behavior
```

## Usage Examples

### Basic Setup (GPO)
```powershell
# Enable dual listing mode
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -Name "WAU_UseDualListing" -Value 1

# Add applications to whitelist
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList" -Name "1" -Value "Microsoft.Teams"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList" -Name "2" -Value "Adobe.Acrobat.Reader.64-bit"

# Add application to blacklist (will override whitelist)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList" -Name "1" -Value "Microsoft.Teams"
```

### Testing Configuration
```powershell
# Run quick test
.\Tests\Test-DualListingQuick.ps1

# Show current configuration
.\Tests\Test-DualListingQuick.ps1 -ShowConfiguration

# Test logic only (no setup)
.\Tests\Test-DualListingQuick.ps1 -TestOnly
```

## Test Coverage

### Unit Tests (`DualListingMode.Tests.ps1`)
- Core logic validation
- Configuration loading
- Error handling
- Edge cases (empty lists, unknown versions)

### Integration Tests (`DualListingMode.Integration.Tests.ps1`)
- End-to-end scenarios
- GPO integration
- Registry configuration
- File-based configuration

### Real-world Testing (`Test-DualListingRealWorld.ps1`)
- Actual winget installations
- Registry configuration
- Upgrade simulation
- Cleanup procedures

### Performance Tests
- Large application lists
- Configuration loading performance
- Memory usage validation

## Common Scenarios

### Scenario 1: Selective Updates
- **Whitelist**: Critical applications only
- **Blacklist**: Known problematic applications
- **Result**: Only critical apps update, problematic apps blocked

### Scenario 2: Department-specific Rules
- **Whitelist**: Department-approved applications
- **Blacklist**: Security-restricted applications
- **Result**: Department flexibility with security oversight

### Scenario 3: Gradual Rollout
- **Whitelist**: All applications
- **Blacklist**: Applications in testing phase
- **Result**: Gradual introduction of new application versions

## Troubleshooting

### Common Issues

1. **Dual listing mode not working**
   - Check registry value: `WAU_UseDualListing = 1`
   - Verify GPO activation: `WAU_ActivateGPOManagement = 1`
   - Review WAU logs for errors

2. **Applications not being blocked**
   - Verify blacklist configuration
   - Check application ID format
   - Ensure blacklist precedence logic

3. **Performance issues**
   - Monitor list sizes
   - Check configuration loading times
   - Review memory usage

### Debugging Commands

```powershell
# Check current configuration
Get-ItemProperty -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate" -Name "WAU_UseDualListing"

# View whitelist
Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList"

# View blacklist
Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList"

# Test with logging
$VerbosePreference = "Continue"
Get-DualListApps -OutdatedApps $apps -Verbose
```

## File Structure

```
Sources/
├── Winget-AutoUpdate/
│   ├── functions/
│   │   ├── Get-DualListApps.ps1        # Core dual listing logic
│   │   ├── Get-WAUConfig.ps1           # Enhanced configuration
│   │   ├── Get-IncludedApps.ps1        # Whitelist loader
│   │   └── Get-ExcludedApps.ps1        # Blacklist loader
│   └── config/
│       ├── included_apps.txt           # File-based whitelist
│       └── excluded_apps.txt           # File-based blacklist
├── Policies/
│   └── ADMX/
│       ├── WAU.admx                    # GPO template
│       └── en-US/
│           └── WAU.adml                # GPO language file
└── Wix/
    └── build.wxs                       # MSI installer config

Tests/
├── DualListingMode.Tests.ps1           # Unit tests
├── DualListingMode.Integration.Tests.ps1 # Integration tests
├── Test-DualListingRealWorld.ps1       # Real-world testing
└── Test-DualListingQuick.ps1           # Quick demo script
```

## Best Practices

1. **Use GPO for Enterprise**: Provides centralized management and auditing
2. **Test Configuration**: Always test with the provided test scripts
3. **Monitor Performance**: Large lists can impact performance
4. **Document Changes**: Keep track of whitelist/blacklist modifications
5. **Regular Review**: Periodically review and update lists
6. **Backup Configuration**: Export registry settings before changes

## Security Considerations

1. **Administrative Access**: Configuration requires admin privileges
2. **Registry Protection**: Secure registry paths from unauthorized access
3. **Audit Trail**: Enable logging for compliance requirements
4. **Change Management**: Implement approval process for list modifications

## Future Enhancements

1. **Web-based Management**: GUI for list management
2. **Conditional Rules**: Time-based or user-based restrictions
3. **Automated List Updates**: Dynamic list updates from external sources
4. **Enhanced Reporting**: Detailed reports on update decisions
5. **Integration APIs**: REST APIs for external management tools

---

This documentation provides a comprehensive guide to the dual listing mode feature. For technical support or feature requests, please refer to the project's issue tracker.
