#Function to get the winget command regarding execution context (User, System...)

Function Get-WingetCmd
{
    [OutputType([String])]
    $WingetCmd = [string]::Empty;

    #Get WinGet Path
    # default winget path (in system context)
    [string]$ps = "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe";

    #default winget path (in user context)
    [string]$pu = "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe";

    try
    {
        #Get Admin Context Winget Location
        $WingetInfo = (Get-Item -Path $ps -ErrorAction Stop).VersionInfo | Sort-Object -Property FileVersionRaw -Descending | Select-Object -First 1;
        #If multiple versions, pick most recent one
        $WingetCmd = $WingetInfo.FileName;
    }
    catch
    {
        #Get User context Winget Location
        if (Test-Path -Path $pu -PathType Leaf)
        {
            $WingetCmd = $pu;
        }
    }
    return $WingetCmd;
}
