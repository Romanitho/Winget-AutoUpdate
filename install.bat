@echo off
powershell -Command "Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File; Start-Process powershell.exe -Argument '-executionpolicy bypass -file """%~dp0Winget-AutoUpdate-Install.ps1"" -Silent'" -Verb RunAs
powershell -Command "Start-Process powershell.exe -Argument '-executionpolicy bypass -file """%~dp0Winget-AutoUpdate-Customisations.ps1"" -Silent'" -Verb RunAs
