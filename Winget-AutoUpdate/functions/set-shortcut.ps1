<#
.Synopsis
   Shortcut deployed from github could be recognized as malicious, LOL!
.DESCRIPTION
   Project Issue: https://github.com/Romanitho/Winget-AutoUpdate/issues/519
   documentation: 
    WshShortcut Object: https://learn.microsoft.com/en-us/previous-versions//xk6kst2k(v=vs.85)?redirectedfrom=MSDN
    Shell link        : https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/16cb4ca1-9339-4d0c-a68d-bf1d6cc0f943?redirectedfrom=MSDN
.EXAMPLE
   To recreate functionaly alternative to ready-made LNK file we will be using this function
.EXAMPLE
   Another example of how to use this cmdlet
.INPUTS
   $SourceExe - path to executable
   $CommandLine - arguments passed to that executable
   $DestinationPath - full path to lnk file (incl extension)
.OUTPUTS
   Output none, LNK file is created using Wscript.Shell.
.NOTES
   There is an alternative way of screating the link using 'New-Item -ItemType SymbolicLink'
.FUNCTIONALITY
   This function creates a shortcut.
#>

enum ShowCommand {
    SW_SHOWNORMAL = 1      # normal
    SW_SHOWMAXIMIZED = 3   # maximized
    SW_SHOWMINNOACTIVE = 7 # minimized
}

function set-shortcut(){
    param ( 
        [string]$SourceExe, 
        [string]$CommandLine, 
        [string]$DestinationPath,
        [int]$ShowCommand
    )
    $WshShell = New-Object -comObject WScript.Shell;
    $Shortcut = $WshShell.CreateShortcut($DestinationPath);
    $Shortcut.TargetPath = $SourceExe;
    $Shortcut.Arguments = $CommandLine;
    $Shortcut.WindowStyle = $ShowCommand
    $Shortcut.Save();
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WshShell) | Out-Null;
}

#region test
    if($false) {
        New-Item -Path "C:\Temp" -Force -ErrorAction SilentlyContinue;
        Set-Content -Path "C:\Temp\test.txt" -Value "it works :)" -Force;
        $DestinationPath  = "C:\Temp\test.lnk";
        $SourceExe = "notepad.exe";
        $CommandLine = "C:\Temp\test.txt";
        set-shortcut `
            -SourceExe $SourceExe `
            -CommandLine $CommandLine `
            -DestinationPath $DestinationPath `
            -ShowCommand ([showcommand]::SW_SHOWMINNOACTIVE)
    }
#endregion
