<# ARRAYS/VARIABLES #>
#App to Run ($RunWait = $False if it shouldn't be waited for)
$Run = ""
$RunSwitch = ""
$RunWait = $True

#Beginning of Process Name to Stop - optional wildcard (*) after, without .exe, multiple: "proc1","proc2"
$Proc = @("")

#Beginning of Process Name to Wait for to End - optional wildcard (*) after, without .exe, multiple: "proc1","proc2"
$Wait = @("")

#Beginning of App Name string to Silently Uninstall (MSI/NSIS/INNO/EXE with defined silent uninstall in registry)
#Multiple: "app1*","app2*", required wildcard (*) after; search is done with "-like"!
$App = @("")

#Beginning of Desktop Link Name to Remove - optional wildcard (*) after, without .lnk, multiple: "lnk1","lnk2"
$Lnk = @("")

#Registry _value_ (DWord/String) to add in existing registry Key (Key created if not existing). Example:
#$AddKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
#$AddValue = "WAU_BypassListForUsers"
#$AddTypeData = "1"
#$AddType = "DWord"
$AddKey = ""
$AddValue = ""
$AddTypeData = ""
$AddType = ""

#Registry _value_ to delete in existing registry Key.
#Value can be omitted for deleting entire Key!. Example:
#$DelKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
#$DelValue = "WAU_BypassListForUsers"
$DelKey = ""
$DelValue = ""

#Remove file/directory, multiple: "file1","file2"
$DelFile = @("")

#Copy file/directory
#Example:
#$CopyFile = "C:\Logfiles"
#$CopyTo = "C:\Drawings\Logs"
$CopyFile = ""
$CopyTo = ""

#Grant "Modify" for directory/file to "Authenticated Users" - multiple: "dir1","dir2"
$GrantPath = @("")

<# FUNCTIONS #>
. $PSScriptRoot\_Mods-Functions.ps1

<# MAIN #>
if ($Run) {
    Invoke-ModsApp $Run $RunSwitch $RunWait
}
if ($Proc) {
    Stop-ModsProc $Proc
}
if ($Wait) {
    Wait-ModsProc $Wait
}
if ($App) {
    Uninstall-ModsApp $App
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
if ($CopyFile -and $CopyTo) {
    Copy-ModsFile $CopyFile $CopyTo
}
if ($GrantPath) {
    Grant-ModsPath $GrantPath
}

<# EXTRAS #>
