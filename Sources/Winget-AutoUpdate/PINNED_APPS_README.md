# WAU Pinned Apps Feature

The Pinned Apps feature allows administrators to pin specific applications to particular versions, preventing WAU from updating them beyond the pinned version. This feature leverages winget's native pin functionality to create update rings and maintain version control across your environment.

## Overview

This feature integrates with winget's built-in pin system to:
- Pin applications to specific versions or version patterns
- Create update rings for staged deployments
- Maintain compliance with specific software versions
- Prevent unwanted updates to critical applications

## Requirements

- Winget version that supports the `pin` command (Windows Package Manager 1.4.0 or later)
- WAU with pin support enabled
- Administrator privileges for pin management

## Configuration Methods

### 1. Local Configuration File

Create a `pinned_apps.txt` file in the WAU installation directory:

```
# WAU Pinned Apps Configuration
# Format: AppID=Version

Microsoft.VisualStudioCode=1.85.*
Google.Chrome=120.*
Microsoft.PowerToys=0.70.*
Adobe.Acrobat.Reader.64-bit=23.008.20470
Mozilla.Firefox=121.*
```

### 2. Group Policy (GPO)

Use the WAU ADMX templates to configure pins via Group Policy:

1. Import the updated WAU.admx template
2. Navigate to: Computer Configuration > Administrative Templates > WAU
3. **Enable "Enable WAU Pin Management"** policy (required)
4. Configure "Application GPO Pinned Apps" policy
5. Add applications in the format: `AppID=Version`

**Important**: Pin management must be explicitly enabled via the "Enable WAU Pin Management" policy before any pin configurations will be processed.

### 3. External Configuration Path

Configure WAU to use an external pin configuration:

- Set `WAU_PinnedAppsPath` to point to a network share or URL
- WAU will download/copy the pin configuration from this location
- Supports both local paths and HTTP URLs

## Version Patterns

The pin feature supports various version patterns:

| Pattern | Description | Example |
|---------|-------------|---------|
| `1.85.0` | Exact version | Pin to exactly version 1.85.0 |
| `1.85.*` | Major.Minor wildcard | Pin to any 1.85.x version |
| `1.*` | Major wildcard | Pin to any 1.x version |
| `>=1.85.0` | Minimum version | Pin to 1.85.0 or higher |

## Configuration Priority

Pin configurations are loaded in the following order (highest to lowest priority):

1. **Group Policy (GPO)** - Centrally managed pins
2. **External Path** - Network or URL-based configuration
3. **Local File** - Local `pinned_apps.txt` file

## Management Tools

### WAU-PinManager.ps1

A PowerShell utility for managing pins:

```powershell
# List all pinned applications
.\WAU-PinManager.ps1 -Action List

# Pin an application to a specific version
.\WAU-PinManager.ps1 -Action Add -AppId "Microsoft.VisualStudioCode" -Version "1.85.*"

# Pin an application to current installed version
.\WAU-PinManager.ps1 -Action Add -AppId "Microsoft.PowerToys"

# Remove a pin
.\WAU-PinManager.ps1 -Action Remove -AppId "Microsoft.VisualStudioCode"

# Remove all pins
.\WAU-PinManager.ps1 -Action Reset
```

### Manual Winget Commands

You can also manage pins directly with winget:

```cmd
# Add a pin
winget pin add --id Microsoft.PowerToys --version 0.70.*

# List pins
winget pin list

# Remove a pin
winget pin remove --id Microsoft.PowerToys

# Reset all pins
winget pin reset --force
```

## Update Rings Implementation

Create different update rings by assigning different pin configurations to computer groups:

### Stable Ring
```
Microsoft.VisualStudioCode=1.84.*
Google.Chrome=119.*
Microsoft.PowerToys=0.69.*
```

### Testing Ring
```
Microsoft.VisualStudioCode=1.85.*
Google.Chrome=120.*
Microsoft.PowerToys=0.70.*
```

### Bleeding Edge Ring
```
# No pins - always get latest versions
```

## How It Works

1. **Pin Loading**: WAU loads pin configuration from GPO, external path, or local file
2. **Pin Application**: Before checking for updates, WAU applies all configured pins using `winget pin add`
3. **Update Check**: WAU runs `winget upgrade` which automatically respects the applied pins
4. **Logging**: All pin operations are logged for troubleshooting

## Logging

Pin operations are logged in the standard WAU log files:

- Pin configuration loading
- Pin application success/failure
- Apps skipped due to pins during updates

Example log entries:
```
Loading WAU pin configurations...
GPO Pin: Microsoft.VisualStudioCode = 1.85.*
Adding pin for Microsoft.VisualStudioCode to version 1.85.*...
Pin operation completed successfully for Microsoft.VisualStudioCode
```

## Troubleshooting

### Pin Support Not Available
- Ensure winget version supports pins (1.4.0+)
- Update Windows Package Manager if needed

### Pins Not Applied
- Check WAU logs for pin application errors
- Verify pin configuration syntax
- Ensure administrator privileges

### Apps Still Updating Despite Pins
- Verify pins are actually applied: `winget pin list`
- Check if app ID matches exactly
- Ensure version pattern is correct

### GPO Pins Not Loading
- Verify GPO is applied: `gpresult /r`
- Check registry: `HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\PinnedApps`
- Ensure WAU_ActivateGPOManagement is enabled

## Best Practices

1. **Test First**: Test pin configurations in a lab environment
2. **Version Patterns**: Use wildcards for flexibility (e.g., `1.85.*` vs `1.85.0`)
3. **Staged Rollouts**: Use update rings for gradual deployments
4. **Monitor Logs**: Regularly check WAU logs for pin-related issues
5. **Documentation**: Document your pin strategy and update rings
6. **Regular Review**: Periodically review and update pin configurations

## Examples

### Enterprise Deployment
```
# Critical applications pinned to stable versions
Microsoft.Office=16.0.16827.*
Adobe.Acrobat.Reader.64-bit=23.008.*
Microsoft.Teams=1.6.*

# Development tools allowed to update more frequently
Microsoft.VisualStudioCode=1.85.*
Git.Git=2.43.*
```

### Educational Environment
```
# Pin educational software to tested versions
Microsoft.Office=16.0.16827.*
Adobe.Acrobat.Reader.64-bit=23.008.*
Mozilla.Firefox=121.*
Google.Chrome=120.*
```

### Development Environment
```
# Pin to specific versions for consistency
Microsoft.VisualStudioCode=1.85.0
Node.js=20.10.0
Git.Git=2.43.0
```

## Integration with Existing WAU Features

The pin feature works seamlessly with existing WAU functionality:

- **Whitelist/Blacklist**: Pins are applied before list filtering
- **Mods**: Custom mods still work with pinned applications
- **User Context**: Pins work in both system and user contexts
- **Notifications**: Standard WAU notifications for pinned apps
- **External Lists**: Can be combined with external list management

## Security Considerations

- Pin configurations via GPO provide centralized control
- External pin paths should use secure connections (HTTPS)
- Regular auditing of pin configurations recommended
- Consider impact of pinning security-critical applications
