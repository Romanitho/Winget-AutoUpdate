@echo off
powershell -Command "Start-Process powershell.exe -Argument '-noprofile -executionpolicy bypass -file """%~dp0WAU-Uninstall.ps1""" '" -Verb RunAs