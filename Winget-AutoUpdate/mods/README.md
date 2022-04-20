# Winget-Install

## Mods

The Mod feature allows you to run an additional script when installing or uninstalling an app.
Just put the script with the App ID followed by the "-install" or "-uninstall" suffix to be considered.  
`AppID-install.ps1` or `AppID-uninstall.ps1`  
and put this in the Mods directory  
> Example:  
> If you want to run a script just after uninstalling FileZilla, call your script like this:
> `TimKosse.FileZilla.Client-uninstall.ps1`

In the case of FileZilla it spawns a process "Un_A.exe" (NullSoft) as a graphical uninstallation and this we will have to wait for completion of before moving on to checking if the uninstallation suceeded or not.
