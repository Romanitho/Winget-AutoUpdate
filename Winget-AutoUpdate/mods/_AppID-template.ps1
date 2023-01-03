<# ARRAYS/VARIABLES #>
#Beginning of Process Name to Stop - optional wildcard (*) after, without .exe, multiple: "proc1","proc2"
$Proc = @("")

#Beginning of Process Name to Wait for to End - optional wildcard (*) after, without .exe, multiple: "proc1","proc2"
$Wait = @("")

#Beginning of App Name string to Silently Uninstall (MSI/NSIS/INNO/EXE with defined silent uninstall in registry)
#Required wildcard (*) after, search is done with "-like"!
$App = ""

#Beginning of Desktop Link Name to Remove - optional wildcard (*) after, without .lnk, multiple: "lnk1","lnk2"
$Lnk = @("")

#Registry _value_ (DWord/String) to add in existing registry Key. Example:
#$AddKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
#$AddValue = "WAU_BypassListForUsers"
#$AddTypeValue = "1"
#$AddType = "DWord"
$AddKey = ""
$AddValue = ""
$AddTypeValue = ""
$AddType = ""

#Registry _value_ to delete in existing registry Key. Example:
#$DelKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
#$DelValue = "WAU_BypassListForUsers"
$DelKey = ""
$DelValue = ""

<# FUNCTIONS #>
. $PSScriptRoot\_Mods-Functions.ps1

<# MAIN #>
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
if ($AddKey -and $AddValue -and $AddTypeValue -and $AddType) {
    Add-ModsReg $AddKey $AddValue $AddTypeValue $AddType
}
if ($DelKey -and $DelValue) {
    Remove-ModsReg $DelKey $DelValue
}

<# EXTRAS #>
