A Directory for placing useful **bins** (**MsiZap.exe** as a really good example) for running via the **Template Function** (https://support.microfocus.com/kb/doc.php?id=7023386):

#$RunWait = $False if it shouldn't be waited for completion. Example:  
#$RunSystem = "$PSScriptRoot\bins\MsiZap.exe"  
#$RunSwitch = "tw! `{GUID}`"  
$Run = ""  
$RunSwitch = ""  
$RunWait = $True  
