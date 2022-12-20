<# ARRAYS/VARIABLES #>
#Beginning of Process Name to Stop - optional wildcard (*) after, without .exe, multiple: "proc1","proc2"
$Proc = @("")

#Beginning of Process Name to Wait for to end - optional wildcard (*) after, without .exe, multiple: "proc1","proc2"
$Wait = @("")

#Beginning of App Name string to Uninstall - required wildcard (*) after!
$App = ""

#Beginning of Desktop Link Name to Remove - optional wildcard (*) after, without .lnk, multiple: "lnk1","lnk2"
$Lnk = @("")

<# FUNCTIONS #>
. $PSScriptRoot\_Common-Functions.ps1

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

<# EXTRAS #>
