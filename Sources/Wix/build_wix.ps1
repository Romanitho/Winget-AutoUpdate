# This is a script to run the wix build.wxs file to create an installer. 
# This expects the context to be the wix directory and the build.wxs file to be in the same directory as this script. 

# Once the .NET SDK and WIX proper are installed, the following commands can be run to build the installer
# wix extension add WixToolset.UI.wixext
# wix extension add WixToolset.Util.wixext

# First sign all resources under the source directory 
# Get my certificate thumbprint
$cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1 
# Now get the winget-autoupdate directory and sign all files

$wingetFiles = Get-ChildItem -Path ..\ -Recurse -File -Include *.exe, *.dll, *.ps1, *.psm1, *.psd1, *.ps1xml 

foreach ($file in $wingetFiles) {
    Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $cert -TimestampServer "http://timestamp.digicert.com"
}
Start-Sleep 3

$OutputFile = ".\WAU.msi"
$BuildVersion = "2.1.1"
$Comment = "Custom Build for CLM"
wix build .\build.wxs -d Version="$BuildVersion" -d Comment="$Comment" -d PreRelease="False" -d NextSemVer="False" -o $OutputFile -arch x64 -ext WixToolset.UI.wixext -ext WixToolset.Util.wixext

# Now sign the output MSI for completeness
Set-AuthenticodeSignature -FilePath $OutputFile -Certificate $cert -TimestampServer "http://timestamp.digicert.com"

Copy-Item $OutputFile "\\$($env:TestComputer)\temp\WAU_TEST" -Verbose 

