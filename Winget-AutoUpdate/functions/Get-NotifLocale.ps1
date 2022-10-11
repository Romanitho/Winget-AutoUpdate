#Function to get locale file for Notification.

Function Get-NotifLocale {
    
    #Get OS locale
    $OSLocale = (Get-Culture).Parent

    #Test if OS locale notif file exists
    $TestOSLocalPath = "$WorkingDir\locale\$($OSLocale.Name).xml"   
    
    #Set OS Local if file exists
    if (Test-Path $TestOSLocalPath) {
        $LocaleDisplayName = $OSLocale.DisplayName
        $LocaleFile = $TestOSLocalPath
    }
    #Set English if file doesn't exist
    else {
        $LocaleDisplayName = "English"
        $LocaleFile = "$WorkingDir\locale\en.xml"
    }

    $CallingScript = (Get-PSCallStack)[2].Command
    Write-Host $CallingScript

    #Get locale XML file content
    [xml]$Script:NotifLocale = Get-Content $LocaleFile -Encoding UTF8 -ErrorAction SilentlyContinue

    #Test if function is not called from "user-run.ps1", then write to log
    $CallingScript = Get-Variable -Scope:1 -Name:MyInvocation -ValueOnly | Select-Object MyCommand, Value
    if (!($CallingScript = "user-run.ps1")) {
        Write-Log "Notification Level: $($WAUConfig.WAU_NotificationLevel). Notification Language: $LocaleDisplayName" "Cyan"
    }

    #Test if new strings exist in $LocaleFile
	if ($null -eq $NotifLocale.local.outputs.output[7].message){
		$LocaleFile = "$WorkingDir\locale\en.xml"
		#Get locale XML file content
		[xml]$Script:NotifLocale = Get-Content $LocaleFile -Encoding UTF8 -ErrorAction SilentlyContinue
	}

}