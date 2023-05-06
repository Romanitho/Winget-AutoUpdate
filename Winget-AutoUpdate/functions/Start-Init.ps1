# Initialisation

function Start-Init {

    #Config console output encoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    $caller = Get-ChildItem $MyInvocation.PSCommandPath | Select-Object -Expand Name
    if ($caller -eq "Winget-Upgrade.ps1") {
        #Log Header
        $Log = "`n##################################################`n#     CHECK FOR APP UPDATES - $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern)`n##################################################"
        $Log | Write-host
        #Logs initialisation
        $Script:LogFile = "$WorkingDir\logs\updates.log"
    }
    elseif ($caller -eq "Winget-AutoUpdate-Install.ps1") {
        $Script:LogFile = "$WingetUpdatePath\logs\updates.log"
    }

    if (!(Test-Path $LogFile)) {
        #Create file if doesn't exist
        New-Item -ItemType File -Path $LogFile -Force | Out-Null

        #Set ACL for users on logfile
        $NewAcl = Get-Acl -Path $LogFile
        $identity = New-Object System.Security.Principal.SecurityIdentifier S-1-5-11
        $fileSystemRights = "Modify"
        $type = "Allow"
        $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
        $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
        $NewAcl.SetAccessRule($fileSystemAccessRule)
        Set-Acl -Path $LogFile -AclObject $NewAcl
    }
    elseif ((Test-Path $LogFile) -and ($caller -eq "Winget-AutoUpdate-Install.ps1")) {
        #Set ACL for users on logfile
        $NewAcl = Get-Acl -Path $LogFile
        $identity = New-Object System.Security.Principal.SecurityIdentifier S-1-5-11
        $fileSystemRights = "Modify"
        $type = "Allow"
        $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
        $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
        $NewAcl.SetAccessRule($fileSystemAccessRule)
        Set-Acl -Path $LogFile -AclObject $NewAcl
    }

    #Check if Intune Management Extension Logs folder and WAU-updates.log exists, make symlink
    if ((Test-Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs") -and !(Test-Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log")) {
        Write-host "`nCreating SymLink for log file (WAU-updates) in Intune Management Extension log folder" -ForegroundColor Yellow
        New-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log" -ItemType SymbolicLink -Value $LogFile -Force -ErrorAction SilentlyContinue | Out-Null
    }
    #Check if Intune Management Extension Logs folder and WAU-install.log exists, make symlink
    if ((Test-Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs") -and (Test-Path "$WorkingDir\logs\install.log") -and !(Test-Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log")) {
        Write-host "`nCreating SymLink for log file (WAU-install) in Intune Management Extension log folder" -ForegroundColor Yellow
        New-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -ItemType SymbolicLink -Value "$WorkingDir\logs\install.log" -Force -ErrorAction SilentlyContinue | Out-Null
    }

    if ($caller -eq "Winget-Upgrade.ps1") {
        #Log file
        $Log | out-file -filepath $LogFile -Append
    }

}
