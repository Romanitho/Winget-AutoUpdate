<# ARRAYS/VARIABLES #>
#App to Run (as SYSTEM)
#$RunWait = $False if it shouldn't be waited for completion. Example:
#$RunSystem = "$PSScriptRoot\bins\MsiZap.exe"
#$RunSwitch = "tw! {GUID}"
$RunSystem = ""
$RunSwitch = ""
$RunWait = $True

#Beginning of Process Name to Stop - optional wildcard (*) after, without .exe, multiple: "proc1","proc2"
$Proc = @("")

#Beginning of Service Name to Stop - multiple: "service1.exe","service2.exe"
$Svc = @("")

#Beginning of Process Name to Wait for to End - optional wildcard (*) after, without .exe, multiple: "proc1","proc2"
$Wait = @("")

#Install App from Winget Repo, multiple: "appID1","appID2". Example:
#$WingetIDInst = @("Microsoft.PowerToys")
$WingetIDInst = @("")

#WingetID to uninstall in default manifest mode (silent if supported)
#Multiple: "ID1","ID2". Example:
#$WingetIDUninst = @("Microsoft.PowerToys")
$WingetIDUninst = @("")

#Beginning of App Name string to Silently Uninstall (MSI/NSIS/INNO/EXE with defined silent uninstall in registry)
#Multiple: "app1*","app2*", required wildcard (*) after; search is done with "-like"!
#Uninstall all versions if there exist several?
$AppUninst = @("")
$AllVersions = $False

#Beginning of Desktop Link Name to Remove - optional wildcard (*) after, without .lnk, multiple: "lnk1","lnk2"
$Lnk = @("")

#Registry _value_ (DWord/String) to add in existing registry Key (Key created if not existing). Example:
#$AddKey = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
#$AddValue = "WAU_BypassListForUsers"
#$AddTypeData = "1"
#$AddType = "DWord"
$AddKey = ""
$AddValue = ""
$AddTypeData = ""
$AddType = ""

#Registry _value_ to delete in existing registry Key.
#Value can be omitted for deleting entire Key!. Example:
#$DelKey = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
#$DelValue = "WAU_BypassListForUsers"
$DelKey = ""
$DelValue = ""

#Remove file/directory, multiple: "file1","file2" Example:
#$DelFile = @("${env:ProgramFiles}\PowerToys\PowerToys.Update.exe")
$DelFile = @("")

#Rename file/directory. Example:
#$RenFile = "${env:ProgramFiles}\PowerToys\PowerToys.Update.exe"
#$NewName = "PowerToys.Update.org"
$RenFile = ""
$NewName = ""

#Copy file/directory. Example:
#$CopyFile = "C:\Logfiles"
#$CopyTo = "C:\Drawings\Logs"
$CopyFile = ""
$CopyTo = ""

#Find/Replace text in file. Example:
#$File = "C:\dummy.txt"
#$FindText = 'brown fox'
#$ReplaceText = 'white fox'
$File = ""
$FindText = ''
$ReplaceText = ''

#Grant "Modify" for directory/file to "Authenticated Users" - multiple: "dir1","dir2"
$GrantPath = @("")

#App to Run (as current logged-on user)
$RunUser = ""
$User = $True

<# FUNCTIONS #>
. $PSScriptRoot\_Mods-Functions.ps1

<# MAIN #>
if ($RunSystem) {
    Invoke-ModsApp $RunSystem $RunSwitch $RunWait ""
}
if ($Proc) {
    Stop-ModsProc $Proc
}
if ($Svc) {
    Stop-ModsSvc $Svc
}
if ($Wait) {
    Wait-ModsProc $Wait
}
if ($WingetIDInst) {
    Install-WingetID $WingetIDInst
}
if ($WingetIDUninst) {
    Uninstall-WingetID $WingetIDUninst
}
if ($AppUninst) {
    Uninstall-ModsApp $AppUninst $AllVersions
}
if ($Lnk) {
    Remove-ModsLnk $Lnk
}
if ($AddKey -and $AddValue -and $AddTypeData -and $AddType) {
    Add-ModsReg $AddKey $AddValue $AddTypeData $AddType
}
if ($DelKey) {
    Remove-ModsReg $DelKey $DelValue
}
if ($DelFile) {
    Remove-ModsFile $DelFile
}
if ($RenFile -and $NewName) {
    Rename-ModsFile $RenFile $NewName
}
if ($CopyFile -and $CopyTo) {
    Copy-ModsFile $CopyFile $CopyTo
}
if ($File -and $FindText -and $ReplaceText) {
    Edit-ModsFile $File $FindText $ReplaceText
}
if ($GrantPath) {
    Grant-ModsPath $GrantPath
}
if ($RunUser) {
    Invoke-ModsApp $RunUser "" "" $User
}

<# EXTRAS #>
