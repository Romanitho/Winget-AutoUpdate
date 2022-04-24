#Function to get locale file for Notification.

Function Get-NotifLocale {
    
    #Get OS locale
    $OSLocale = (Get-Culture).Parent

    #Test if OS locale notif file exists
    $TestOSLocalPath = "$WorkingDir\locale\$($OSLocale.Name).xml"   
    
    #Set OS Local if file exists
    if(Test-Path $TestOSLocalPath){
        $LocaleDisplayName = $OSLocale.DisplayName
        $LocaleFile = $TestOSLocalPath
    }
    #Set English if file doesn't exist
    else{
        $LocaleDisplayName = "English"
        $LocaleFile = "$WorkingDir\locale\en.xml"
    }

    #Get locale XML file content
    Write-Log "Notification Level: $NotificationLevel. Notification Language: $LocaleDisplayName" "Cyan"
    [xml]$Script:NotifLocale = Get-Content $LocaleFile -Encoding UTF8 -ErrorAction SilentlyContinue

}