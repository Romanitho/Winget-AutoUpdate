#Requires -RunAsAdministrator

<#
.SYNOPSIS
    WAU Pin Manager - Utility to manage Winget application pins for WAU
.DESCRIPTION
    This script provides a command-line interface to manage pinned applications
    for Winget-AutoUpdate (WAU). It allows adding, removing, and listing pins.
.PARAMETER Action
    The action to perform: Add, Remove, List, or Reset
.PARAMETER AppId
    The application ID to pin/unpin (required for Add/Remove actions)
.PARAMETER Version
    The version to pin to (optional for Add action, uses current version if not specified)
.PARAMETER ConfigFile
    Path to the pin configuration file (optional, defaults to local pinned_apps.txt)
.EXAMPLE
    .\WAU-PinManager.ps1 -Action List
    Lists all currently pinned applications
.EXAMPLE
    .\WAU-PinManager.ps1 -Action Add -AppId "Microsoft.VisualStudioCode" -Version "1.85.*"
    Pins Visual Studio Code to version 1.85.*
.EXAMPLE
    .\WAU-PinManager.ps1 -Action Remove -AppId "Microsoft.VisualStudioCode"
    Removes the pin for Visual Studio Code
.EXAMPLE
    .\WAU-PinManager.ps1 -Action Reset
    Removes all pins
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Add", "Remove", "List", "Reset")]
    [string]$Action,
    
    [Parameter(Mandatory=$false)]
    [string]$AppId,
    
    [Parameter(Mandatory=$false)]
    [string]$Version,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile
)

# Get the Working Dir
[string]$Script:WorkingDir = $PSScriptRoot;

# Get Functions
Get-ChildItem -Path "$($Script:WorkingDir)\functions" -File -Filter "*.ps1" -Depth 0 | ForEach-Object { . $_.FullName; }

# Initialize logging
Initialize-WAULogging -LogFileName "pin-manager.log"

# Get Winget command
[string]$Script:Winget = Get-WingetCmd;

if (!$Script:Winget) {
    Write-Host "Error: Winget not found or not available" -ForegroundColor Red
    exit 1
}

# Test pin support
if (!(Test-WingetPinSupport)) {
    Write-Host "Error: Winget pin support not available in this version" -ForegroundColor Red
    exit 1
}

Write-Host "WAU Pin Manager" -ForegroundColor Cyan
Write-Host "===============" -ForegroundColor Cyan

switch ($Action) {
    "List" {
        Write-Host "Listing currently pinned applications..." -ForegroundColor Yellow
        
        $pinnedApps = Get-WingetPinnedApps
        
        if ($pinnedApps.Count -eq 0) {
            Write-Host "No applications are currently pinned." -ForegroundColor Gray
        }
        else {
            Write-Host "Currently pinned applications:" -ForegroundColor Green
            Write-Host ""
            Write-Host "Name".PadRight(40) + "App ID".PadRight(40) + "Version".PadRight(20) + "Source" -ForegroundColor White
            Write-Host ("-" * 120) -ForegroundColor Gray
            
            foreach ($app in $pinnedApps) {
                Write-Host $app.Name.PadRight(40) + $app.Id.PadRight(40) + $app.Version.PadRight(20) + $app.Source -ForegroundColor White
            }
        }
    }
    
    "Add" {
        if (!$AppId) {
            Write-Host "Error: AppId is required for Add action" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Adding pin for application: $AppId" -ForegroundColor Yellow
        
        $success = Set-WingetPin -Id $AppId -Version $Version -Action "Add"
        
        if ($success) {
            if ($Version) {
                Write-Host "Successfully pinned $AppId to version $Version" -ForegroundColor Green
            }
            else {
                Write-Host "Successfully pinned $AppId to current installed version" -ForegroundColor Green
            }
        }
        else {
            Write-Host "Failed to pin $AppId" -ForegroundColor Red
            exit 1
        }
    }
    
    "Remove" {
        if (!$AppId) {
            Write-Host "Error: AppId is required for Remove action" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Removing pin for application: $AppId" -ForegroundColor Yellow
        
        $success = Set-WingetPin -Id $AppId -Action "Remove"
        
        if ($success) {
            Write-Host "Successfully removed pin for $AppId" -ForegroundColor Green
        }
        else {
            Write-Host "Failed to remove pin for $AppId" -ForegroundColor Red
            exit 1
        }
    }
    
    "Reset" {
        Write-Host "Removing all application pins..." -ForegroundColor Yellow
        Write-Host "Are you sure you want to remove ALL pins? (y/N): " -ForegroundColor Red -NoNewline
        
        $confirmation = Read-Host
        
        if ($confirmation -eq "y" -or $confirmation -eq "Y") {
            $success = Remove-AllWingetPins -Force
            
            if ($success) {
                Write-Host "Successfully removed all pins" -ForegroundColor Green
            }
            else {
                Write-Host "Failed to remove all pins" -ForegroundColor Red
                exit 1
            }
        }
        else {
            Write-Host "Operation cancelled" -ForegroundColor Gray
        }
    }
}

Write-Host ""
Write-Host "Pin management operation completed." -ForegroundColor Cyan
