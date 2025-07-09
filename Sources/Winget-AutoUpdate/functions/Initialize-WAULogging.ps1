#Function to initialize WAU logging environment when running standalone

Function Initialize-WAULogging {
    
    Param(
        [Parameter(Mandatory=$false)]
        [string]$LogFileName = "pin-operations.log"
    )
    
    # Check if LogFile is already set (running within main WAU context)
    if ($Script:LogFile -and (Test-Path (Split-Path $Script:LogFile -Parent) -PathType Container)) {
        return $Script:LogFile
    }
    
    # Initialize for standalone execution
    if (-not $Script:WorkingDir) {
        $Script:WorkingDir = $PSScriptRoot
        if ($Script:WorkingDir.EndsWith('\functions')) {
            $Script:WorkingDir = Split-Path $Script:WorkingDir -Parent
        }
    }
    
    # Create logs directory if it doesn't exist
    $LogsDir = Join-Path $Script:WorkingDir "logs"
    if (!(Test-Path $LogsDir -PathType Container)) {
        New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
    }
    
    # Set the log file path
    $Script:LogFile = Join-Path $LogsDir $LogFileName
    
    return $Script:LogFile
}
