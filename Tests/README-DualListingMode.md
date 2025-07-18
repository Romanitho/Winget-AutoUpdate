# Winget-AutoUpdate Dual Listing Mode

## Overview

The Dual Listing Mode feature allows Winget-AutoUpdate (WAU) to use both whitelist and blacklist configurations simultaneously. This provides more granular control over which applications can be updated, especially useful in enterprise environments where you may want to:

- Allow most applications to update but deny specific ones on certain device groups
- Use different policies for different organizational units
- Implement security controls by combining allow and deny lists

## Key Features

### 🔀 Dual Operation Mode
- **Whitelist + Blacklist**: Use both lists together for maximum control
- **Blacklist Priority**: Blacklist always takes precedence over whitelist
- **Flexible Configuration**: Configure via GPO, registry, or files

### 🛡️ Security-First Design
- **Deny-by-Default**: When using dual mode, apps must be explicitly allowed
- **Blacklist Precedence**: Security restrictions override permissions
- **Audit Trail**: Comprehensive logging of all decisions

### 🏢 Enterprise Ready
- **GPO Integration**: Full Group Policy support
- **Registry Configuration**: Direct registry control
- **File-Based Setup**: Simple file-based configuration
- **Wildcard Support**: Use patterns like `Microsoft.*` for flexibility

## Configuration Methods

### 1. Group Policy (GPO) Configuration

The most common method for enterprise deployments:

```xml
<!-- Enable dual listing mode -->
<policy name="UseDualListing_Enable" class="Machine">
    <enabledValue><decimal value="1" /></enabledValue>
</policy>

<!-- Configure whitelist -->
<policy name="WhiteList_Enable" class="Machine">
    <elements>
        <list id="WhiteList" key="Software\Policies\Romanitho\Winget-AutoUpdate\WhiteList">
            <item>Microsoft.PowerShell</item>
            <item>Microsoft.VisualStudioCode</item>
            <item>7zip.7zip</item>
        </list>
    </elements>
</policy>

<!-- Configure blacklist -->
<policy name="BlackList_Enable" class="Machine">
    <elements>
        <list id="BlackList" key="Software\Policies\Romanitho\Winget-AutoUpdate\BlackList">
            <item>Mozilla.Firefox</item>
            <item>Google.Chrome</item>
        </list>
    </elements>
</policy>
```

### 2. Registry Configuration

For direct registry control:

```powershell
# Enable dual listing mode
New-ItemProperty -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate" -Name "WAU_UseDualListing" -Value 1 -Type DWord

# Configure via files (whitelist and blacklist files in install directory)
# Files: included_apps.txt and excluded_apps.txt
```

### 3. File-Based Configuration

Simple file-based setup:

**included_apps.txt:**
```
Microsoft.PowerShell
Microsoft.VisualStudioCode
7zip.7zip
Git.Git
```

**excluded_apps.txt:**
```
Mozilla.Firefox
Google.Chrome
Microsoft.Edge
```

## How It Works

### Decision Logic

When dual listing mode is enabled, WAU follows this decision process:

1. **Check Version**: Skip apps with "Unknown" version
2. **Check Blacklist**: If app is in blacklist → **SKIP** (blacklist wins)
3. **Check Whitelist**: If whitelist exists and app is in whitelist → **UPDATE**
4. **No Whitelist**: If no whitelist configured → **UPDATE** (not in blacklist)
5. **Not in Whitelist**: If whitelist exists but app not in it → **SKIP**

### Wildcard Support

Both lists support wildcard patterns:

```
Microsoft.*          # All Microsoft apps
Mozilla.Firefox*     # All Firefox channels
*.Teams             # All Teams apps
```

### Example Scenarios

#### Scenario 1: Allow most apps, block browsers on kiosks
```
Whitelist: Microsoft.*, Adobe.*, 7zip.*
Blacklist: Mozilla.Firefox, Google.Chrome, Microsoft.Edge
```

#### Scenario 2: Allow specific apps, block TeamViewer except on admin machines
```
Whitelist: Microsoft.PowerShell, Microsoft.VisualStudioCode, TeamViewer.TeamViewer
Blacklist: TeamViewer.TeamViewer  # Overridden by whitelist on admin machines
```

## Testing

### Running Tests

Use the provided test runner:

```powershell
# Run all tests
.\Tests\Run-DualListingTests.ps1

# Run only unit tests
.\Tests\Run-DualListingTests.ps1 -TestType Unit

# Run with detailed reporting
.\Tests\Run-DualListingTests.ps1 -GenerateReport -OutputPath "C:\TestResults"
```

### Test Coverage

The test suite includes:

- **Unit Tests**: Core functionality testing
- **Integration Tests**: Configuration method testing
- **Performance Tests**: Large-scale app list testing
- **Edge Case Tests**: Error handling and boundary conditions
- **Real-World Scenarios**: Enterprise deployment scenarios

### Test Files

- `DualListingMode.Tests.ps1` - Main unit tests
- `DualListingMode.Integration.Tests.ps1` - Integration tests
- `DualListingMode.Helpers.ps1` - Test helper functions
- `Run-DualListingTests.ps1` - Test runner script

## Installation & Deployment

### MSI Installation

The dual listing mode is included in the standard WAU MSI installer:

```cmd
msiexec /i "WAU.msi" USEDUALLISTING=1
```

### Manual Configuration

Enable dual listing mode manually:

```powershell
# Set registry value
Set-ItemProperty -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate" -Name "WAU_UseDualListing" -Value 1

# Create list files
"Microsoft.PowerShell" | Out-File -FilePath "C:\Program Files\WAU\included_apps.txt"
"Mozilla.Firefox" | Out-File -FilePath "C:\Program Files\WAU\excluded_apps.txt"
```

## Troubleshooting

### Common Issues

1. **Apps not updating despite being in whitelist**
   - Check if app is also in blacklist (blacklist takes precedence)
   - Verify app ID spelling and case sensitivity

2. **Configuration not taking effect**
   - Verify GPO precedence (GPO > Registry > Files)
   - Check WAU service restart after configuration changes

3. **Wildcard patterns not working**
   - Ensure correct PowerShell wildcard syntax (`*` not regex)
   - Test patterns using `"AppId" -like "Pattern"`

### Debug Logging

Enable detailed logging to troubleshoot:

```powershell
# Check WAU logs
Get-Content "C:\Program Files\WAU\logs\install.log"
Get-Content "C:\Program Files\WAU\logs\updates.log"
```

### Validation Commands

Verify configuration:

```powershell
# Check dual listing mode status
Get-ItemProperty -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate" -Name "WAU_UseDualListing"

# Check GPO settings
Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -Name "WAU_UseDualListing"

# Validate list files
Get-Content "C:\Program Files\WAU\included_apps.txt"
Get-Content "C:\Program Files\WAU\excluded_apps.txt"
```

## Performance Considerations

- **Large Lists**: Tested with 1000+ apps, performance remains acceptable
- **Wildcard Patterns**: Minimal performance impact for reasonable patterns
- **Memory Usage**: Efficient array operations for list processing

## Security Considerations

- **Blacklist Priority**: Ensures security restrictions can't be bypassed
- **Input Validation**: All app IDs are validated before processing
- **Audit Logging**: All decisions are logged for compliance

## Contributing

When contributing to dual listing mode:

1. **Run Tests**: Always run the full test suite before submitting
2. **Add Tests**: Include tests for new functionality
3. **Document Changes**: Update this README for any behavioral changes
4. **Performance**: Consider performance impact of changes

## API Reference

### Key Functions

- `Get-DualListApps` - Main processing function
- `Get-IncludedApps` - Retrieves whitelist
- `Get-ExcludedApps` - Retrieves blacklist
- `Get-WAUConfig` - Gets configuration settings

### Configuration Keys

- `WAU_UseDualListing` - Enable/disable dual listing mode
- `WAU_UseWhiteList` - Legacy whitelist-only mode
- `WAU_ListPath` - External list path configuration

## Version History

### v1.20.0+
- Initial dual listing mode implementation
- GPO, Registry, and File configuration support
- Comprehensive test suite
- Performance optimizations

## License

This feature is part of Winget-AutoUpdate and follows the same license terms.
