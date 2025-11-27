<#
.SYNOPSIS
    Retrieves the notification locale file for the current OS language.

.DESCRIPTION
    Loads the appropriate XML locale file for toast notifications based
    on the operating system's UI culture. Falls back to English if the
    OS locale is not available.

.OUTPUTS
    String containing the display name of the selected locale.

.EXAMPLE
    $localeName = Get-NotifLocale

.NOTES
    Sets the script-scoped $NotifLocale variable with the loaded XML content.
    Locale files are stored in the locale subfolder.
#>
Function Get-NotifLocale {

    # Get the OS UI culture (parent culture for regional variants)
    $OSLocale = (Get-UICulture).Parent

    # Build path to locale-specific notification file
    $TestOSLocalPath = "$WorkingDir\locale\$($OSLocale.Name).xml"

    # Use OS locale if file exists, otherwise fall back to English
    if (Test-Path $TestOSLocalPath) {
        $LocaleDisplayName = $OSLocale.DisplayName
        $LocaleFile = $TestOSLocalPath
    }
    else {
        $LocaleDisplayName = "English"
        $LocaleFile = "$WorkingDir\locale\en.xml"
    }

    # Load the locale XML file into script scope for notification messages
    [xml]$Script:NotifLocale = Get-Content $LocaleFile -Encoding UTF8 -ErrorAction SilentlyContinue

    # Return the language display name
    return $LocaleDisplayName

}
