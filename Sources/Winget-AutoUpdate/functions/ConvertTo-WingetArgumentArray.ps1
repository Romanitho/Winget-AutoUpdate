<#
.SYNOPSIS
    Parses a string of winget arguments respecting quotes and spaces.

.DESCRIPTION
    Splits a string of winget command-line arguments into an array,
    properly handling both single and double quotes, multiple spaces,
    and quoted values containing spaces.

.PARAMETER ArgumentString
    The raw argument string to parse (e.g., "--locale en-US --skip-dependencies")

.OUTPUTS
    Array of individual argument strings

.EXAMPLE
    ConvertTo-WingetArgumentArray "--skip-dependencies"
    Returns: @("--skip-dependencies")

.EXAMPLE
    ConvertTo-WingetArgumentArray '--locale "en-US" --architecture x64'
    Returns: @("--locale", "en-US", "--architecture", "x64")

.EXAMPLE
    ConvertTo-WingetArgumentArray "--override '-sfx_nu /sAll /msi EULA_ACCEPT=YES'"
    Returns: @("--override", "-sfx_nu /sAll /msi EULA_ACCEPT=YES")
#>
function ConvertTo-WingetArgumentArray {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ArgumentString
    )
    
    # Return empty array if input is null or whitespace
    if ([string]::IsNullOrWhiteSpace($ArgumentString)) {
        return @()
    }
    
    $ArgumentString = $ArgumentString.Trim()
    
    # Regex pattern that handles:
    # - Double quoted strings: "value with spaces"
    # - Single quoted strings: 'value with spaces'
    # - Unquoted arguments: --flag or value
    # Pattern explanation:
    #   "([^"]*)"  - Captures content between double quotes (group 1)
    #   '([^']*)'  - Captures content between single quotes (group 2)
    #   (\S+)      - Captures non-whitespace sequences (group 3)
    $pattern = '(?:"([^"]*)"|''([^'']*)''|(\S+))'
    
    try {
        # Use [regex]::Matches() to find all argument tokens
        $regex = [regex]::new($pattern)
        $regexMatches = $regex.Matches($ArgumentString)
        
        $result = @()
        foreach ($match in $regexMatches) {
            # Get the captured value from whichever group matched
            $value = if ($match.Groups[1].Success) { 
                # Double-quoted value
                $match.Groups[1].Value 
            } 
            elseif ($match.Groups[2].Success) { 
                # Single-quoted value
                $match.Groups[2].Value 
            } 
            else { 
                # Unquoted value
                $match.Groups[3].Value 
            }
            
            # Only add non-empty values
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $result += $value
            }
        }
        
        return $result
    }
    catch {
        Write-ToLog "Warning: Failed to parse arguments '$ArgumentString' - Error: $($_.Exception.Message)" "Yellow"
        Write-ToLog "Falling back to simple space split" "Yellow"
        
        # Fallback to simple split if regex parsing fails
        $fallbackResult = $ArgumentString.Trim() -split '\s+'
        return $fallbackResult
    }
}
