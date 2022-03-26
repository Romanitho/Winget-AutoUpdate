function Get-WAUCurrentVersion{
    #Get current installed version
    [xml]$About = Get-Content "$WorkingDir\config\about.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
    $Script:WAUCurrentVersion = $About.app.version
}