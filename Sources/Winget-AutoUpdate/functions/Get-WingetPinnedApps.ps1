#Function to get currently pinned apps from winget

Function Get-WingetPinnedApps {

    class PinnedApp {
        [string]$Name
        [string]$Id
        [string]$Version
        [string]$Source
    }

    # Initialize logging if not already set
    Initialize-WAULogging -LogFileName "pin-operations.log"

    try {
        Write-ToLog "Getting currently pinned apps from winget..." "Yellow"
        
        # Execute winget pin list command
        $pinListResult = & $Winget pin list | Where-Object { $_ -notlike "   *" } | Out-String
        
        # Check if any pins exist
        if (!($pinListResult -match "-----")) {
            Write-ToLog "No pinned apps found in winget." "Gray"
            return @()
        }
        
        # Split winget output to lines
        $lines = $pinListResult.Split([Environment]::NewLine) | Where-Object { $_ }
        
        # Find the line that starts with "------"
        $fl = 0
        while (-not $lines[$fl].StartsWith("-----")) {
            $fl++
        }
        
        # Get header line
        $fl = $fl - 1
        
        # Get header titles
        $index = $lines[$fl] -split '(?<=\s)(?!\s)'
        
        # Calculate column positions
        $idStart = $($index[0] -replace '[\u4e00-\u9fa5]', '**').Length
        $versionStart = $idStart + $($index[1] -replace '[\u4e00-\u9fa5]', '**').Length
        $sourceStart = $versionStart + $($index[2] -replace '[\u4e00-\u9fa5]', '**').Length
        
        # Parse pinned apps
        $pinnedList = @()
        For ($i = $fl + 2; $i -lt $lines.Length; $i++) {
            $line = $lines[$i] -replace "[\u2026]", " " # Fix "..." in long names
            
            if ($line.StartsWith("-----")) {
                # Handle multiple sections if they exist
                $fl = $i - 1
                $index = $lines[$fl] -split '(?<=\s)(?!\s)'
                $idStart = $($index[0] -replace '[\u4e00-\u9fa5]', '**').Length
                $versionStart = $idStart + $($index[1] -replace '[\u4e00-\u9fa5]', '**').Length
                $sourceStart = $versionStart + $($index[2] -replace '[\u4e00-\u9fa5]', '**').Length
            }
            
            # Check if line contains app data (has dots indicating package ID)
            if ($line -match "\w\.\w") {
                $pinnedApp = [PinnedApp]::new()
                
                # Handle non-latin characters
                $nameDeclination = $($line.Substring(0, $idStart) -replace '[\u4e00-\u9fa5]', '**').Length - $line.Substring(0, $idStart).Length
                
                $pinnedApp.Name = $line.Substring(0, $idStart - $nameDeclination).TrimEnd()
                $pinnedApp.Id = $line.Substring($idStart - $nameDeclination, $versionStart - $idStart).TrimEnd()
                $pinnedApp.Version = $line.Substring($versionStart - $nameDeclination, $sourceStart - $versionStart).TrimEnd()
                $pinnedApp.Source = $line.Substring($sourceStart - $nameDeclination).TrimEnd()
                
                # Add to list
                $pinnedList += $pinnedApp
            }
        }
        
        if ($pinnedList.Count -gt 0) {
            Write-ToLog "Found $($pinnedList.Count) pinned apps:" "Green"
            foreach ($pin in $pinnedList) {
                Write-ToLog "  - $($pin.Name) ($($pin.Id)) pinned to version $($pin.Version)" "Gray"
            }
        }
        
        return $pinnedList
        
    }
    catch {
        Write-ToLog "Error getting pinned apps: $($_.Exception.Message)" "Red"
        return @()
    }
}
