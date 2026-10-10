<#
.SYNOPSIS
    Compares two Winget version strings.

.DESCRIPTION
    Compares two version strings segment by segment (separated by dots or hyphens).
    Unlike strict SemVer or [Version], handles arbitrary dotted numeric and alphanumeric
    segments without throwing exceptions on non-standard formats.

.PARAMETER A
    The first version string to compare.

.PARAMETER B
    The second version string to compare.

.OUTPUTS
    Integer: -1 if A < B, 0 if A == B, 1 if A > B.

.EXAMPLE
    Compare-WingetVersion -A "1.0.0" -B "1.1.0"   # Returns -1

.EXAMPLE
    Compare-WingetVersion -A "24.07" -B "23.01"   # Returns 1
#>
function Compare-WingetVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$A,
        [Parameter(Mandatory = $true)][string]$B
    )

    $segA = $A -split '[\.\-]'
    $segB = $B -split '[\.\-]'
    $max  = [Math]::Max($segA.Count, $segB.Count)

    for ($i = 0; $i -lt $max; $i++) {
        $sa = if ($i -lt $segA.Count) { $segA[$i] } else { '' }
        $sb = if ($i -lt $segB.Count) { $segB[$i] } else { '' }

        $na = 0; $nb = 0
        $isNumA = [int]::TryParse($sa, [ref]$na)
        $isNumB = [int]::TryParse($sb, [ref]$nb)

        if ($isNumA -and $isNumB) {
            if ($na -ne $nb) { return [Math]::Sign($na - $nb) }
        }
        else {
            $cmp = [string]::Compare($sa, $sb, [System.StringComparison]::OrdinalIgnoreCase)
            if ($cmp -ne 0) { return [Math]::Sign($cmp) }
        }
    }
    return 0
}
