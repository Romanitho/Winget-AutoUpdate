function Update-WAU {

    $OnClickAction = "https://github.com/Romanitho/$($GitHub_Repo)/releases"
    $Button1Text = $NotifLocale.local.outputs.output[10].message

    #Send available update notification
    $Title = $NotifLocale.local.outputs.output[2].title -f "Winget-AutoUpdate"
    $Message = $NotifLocale.local.outputs.output[2].message -f $WAUCurrentVersion, $WAUAvailableVersion
    $MessageType = "info"
    Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text

    #Run WAU update
    try {
        Write-ToLog "Downloading the GitHub Repository version $WAUAvailableVersion" "Cyan"

        #Create an unpredictable temp folder for security reasons
        $MsiFolder = "$env:temp\WAU_$(Get-Date -Format yyyyMMddHHmmss)"
        New-Item -ItemType Directory -Path $MsiFolder

        #Download the msi
        $MsiFile = Join-Path $MsiFolder "WAU.msi"
        Invoke-RestMethod -Uri "https://github.com/Romanitho/Winget-AutoUpdate/releases/download/v$($WAUAvailableVersion)/WAU.msi" -OutFile $MsiFile

        #Update WAU
        Write-ToLog "Updating WAU..." "Yellow"
        Start-Process msiexec.exe -ArgumentList "/i $MsiFile /qn /L*v ""$WorkingDir\logs\WAU-Installer.log"" RUN_WAU=YES INSTALLDIR=""$WorkingDir""" -Wait

        #Send success Notif
        Write-ToLog "WAU Update completed. Rerunning WAU..." "Green"
        $Title = $NotifLocale.local.outputs.output[3].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[3].message -f $WAUAvailableVersion
        $MessageType = "success"
        Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text

        #Remove temp folder and content
        Remove-Item $MsiFolder -Recurse -Force

        exit 0
    }

    catch {

        #Send Error Notif
        $Title = $NotifLocale.local.outputs.output[4].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[4].message
        $MessageType = "error"
        Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text
        Write-ToLog "WAU Update failed" "Red"

    }

}