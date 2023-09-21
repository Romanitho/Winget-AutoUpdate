@echo off

::::::::::::::::::::::::::::
:: Put WAU Arguments here ::
::::::::::::::::::::::::::::

SET arguments=-Uninstall


::::::::::::::::::::::::::::
:: Run Powershell Script  ::
::::::::::::::::::::::::::::

SET PowershellCmd=Start-Process powershell.exe -Verb RunAs -Argument '-noprofile -executionpolicy bypass -file "%~dp0Winget-AutoUpdate-Install.ps1" %arguments%
powershell -Command "& {Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File; %PowershellCmd%'}"
