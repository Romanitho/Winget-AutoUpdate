#Function to make actions post WAU update

function Invoke-PostUpdateActions {

    Write-Log "Running Post Update actions..." "yellow"
    
    #Create WAU Regkey if not present
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
    if (!(test-path $regPath)) {
        New-Item $regPath -Force
        New-ItemProperty $regPath -Name DisplayName -Value "Winget-AutoUpdate (WAU)" -Force
        New-ItemProperty $regPath -Name NoModify -Value 1 -Force
        New-ItemProperty $regPath -Name NoRepair -Value 1 -Force
        New-ItemProperty $regPath -Name Publisher -Value "Romanitho" -Force
        New-ItemProperty $regPath -Name URLInfoAbout -Value "https://github.com/Romanitho/Winget-AutoUpdate" -Force
        New-ItemProperty $regPath -Name InstallLocation -Value $WorkingDir -Force
        New-ItemProperty $regPath -Name UninstallString -Value "$WorkingDir\WAU-Uninstall.bat" -Force
        New-ItemProperty $regPath -Name QuietUninstallString -Value "$WorkingDir\WAU-Uninstall.bat" -Force
        New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 0 -PropertyType DWord -Force
    }
    
    #Convert about.xml if exists (previous WAU versions) to reg
    $WAUAboutPath = "$WorkingDir\config\about.xml"
    if (test-path $WAUAboutPath) {
        [xml]$About = Get-Content $WAUAboutPath -Encoding UTF8 -ErrorAction SilentlyContinue
        New-ItemProperty $regPath -Name DisplayVersion -Value $About.app.version -Force
        New-ItemProperty $regPath -Name VersionMajor -Value ([version]$About.app.version).Major -Force
        New-ItemProperty $regPath -Name VersionMinor -Value ([version]$About.app.version).Minor -Force

        #Remove file once converted
        Remove-Item $WAUAboutPath -Force -Confirm:$false
    }

    #Convert config.xml if exists (previous WAU versions) to reg
    $WAUConfigPath = "$WorkingDir\config\config.xml"
    if (test-path $WAUConfigPath) {
        [xml]$Config = Get-Content $WAUConfigPath -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($Config.app.WAUautoupdate -eq "False") {New-ItemProperty $regPath -Name WAU_DisableAutoUpdate -Value 1 -Force}
        if ($Config.app.NotificationLevel) {New-ItemProperty $regPath -Name WAU_NotificationLevel -Value $Config.app.NotificationLevel -Force}
        if ($Config.app.UseWAUWhiteList -eq "True") {New-ItemProperty $regPath -Name WAU_UseWhiteList -Value 1 -PropertyType DWord -Force}
        if ($Config.app.WAUprerelease -eq "True") {New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 1 -PropertyType DWord -Force}

        #Remove file once converted
        Remove-Item $WAUConfigPath -Force -Confirm:$false
    }

    #Remove old functions
    $FileNames = @(
        "$WorkingDir\functions\Get-WAUConfig.ps1",
        "$WorkingDir\functions\Get-WAUCurrentVersion.ps1",
        "$WorkingDir\functions\Get-WAUUpdateStatus.ps1"
    )
    foreach ($FileName in $FileNames){
        if (Test-Path $FileName) {
            Remove-Item $FileName -Force -Confirm:$false
        }
    }

    #Reset WAU_UpdatePostActions Value
    $WAUConfig | New-ItemProperty -Name WAU_PostUpdateActions -Value 0 -Force

    #Get updated WAU Config
    $Script:WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"

}