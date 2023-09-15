#Function to get the locale file for notifications

Function Get-NotifLocale {

    # Get OS locale
    $OSLocale = (Get-UICulture).Parent

    # Test if OS locale notif file exists
    $TestOSLocalPath = ('{0}\locale\{1}.xml' -f $WorkingDir, $OSLocale.Name)

    # Set OS Local if file exists
    if (Test-Path -Path $TestOSLocalPath -ErrorAction SilentlyContinue) {
        $LocaleDisplayName = $OSLocale.DisplayName
        $LocaleFile = $TestOSLocalPath
    }
    else {
    # Set English if file doesn't exist
        $LocaleDisplayName = 'English'
        $LocaleFile = ('{0}\locale\en.xml' -f $WorkingDir)
    }

    # Get locale XML file content
    [xml]$Script:NotifLocale = (Get-Content -Path $LocaleFile -Encoding UTF8 -ErrorAction SilentlyContinue)

    # Rerturn langague display name
    Return $LocaleDisplayName

}
