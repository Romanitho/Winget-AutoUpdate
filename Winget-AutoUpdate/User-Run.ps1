<#
      .SYNOPSIS
      Handle user interaction from shortcuts and show a Toast notification

      .DESCRIPTION
      Act on shortcut run (DEFAULT: Check for updated Apps)

      .PARAMETER Logs
      Open the Log file from Winget-AutoUpdate installation location

      .PARAMETER Help
      Open the Web Help page
      https://github.com/Romanitho/Winget-AutoUpdate

      .EXAMPLE
      .\user-run.ps1 -Logs

#>

[CmdletBinding()]
param(
    [Switch] $Logs = $False,
    [Switch] $Help = $False
)

function Test-WAUisRunning 
{
   If (((Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue).State -eq 'Running') -or ((Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -ErrorAction SilentlyContinue).State -eq 'Running')) 
   {
      Return $True
   }
}

<# MAIN #>

#Get Working Dir
$Script:WorkingDir = $PSScriptRoot

#Load external functions
. $WorkingDir\functions\Get-NotifLocale.ps1
. $WorkingDir\functions\Start-NotifTask.ps1

#Get Toast Locale function
Get-NotifLocale

#Set common variables
$OnClickAction = ('{0}\logs\updates.log' -f $WorkingDir)
$Button1Text = $NotifLocale.local.outputs.output[11].message

if ($Logs) 
{
   if (Test-Path -Path ('{0}\logs\updates.log' -f $WorkingDir)) 
   {
      Invoke-Item -Path ('{0}\logs\updates.log' -f $WorkingDir)
   }
   else 
   {
      #Not available yet
      $Message = $NotifLocale.local.outputs.output[5].message
      $MessageType = 'warning'
      Start-NotifTask -Message $Message -MessageType $MessageType -UserRun
   }
}
elseif ($Help) 
{
   Start-Process -FilePath 'https://github.com/Romanitho/Winget-AutoUpdate'
}
else 
{
   try 
   {
      # Check if WAU is currently running
      if (Test-WAUisRunning) 
      {
         $Message = $NotifLocale.local.outputs.output[8].message
         $MessageType = 'warning'
         Start-NotifTask -Message $Message -MessageType $MessageType -Button1Text $Button1Text -Button1Action $OnClickAction -ButtonDismiss -UserRun
         break
      }
      # Run scheduled task
      Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction Stop | Start-ScheduledTask -ErrorAction Stop
      # Starting check - Send notification
      $Message = $NotifLocale.local.outputs.output[6].message
      $MessageType = 'info'
      Start-NotifTask -Message $Message -MessageType $MessageType -Button1Text $Button1Text -Button1Action $OnClickAction -ButtonDismiss -UserRun
      # Sleep until the task is done
      While (Test-WAUisRunning) 
      {
         Start-Sleep -Seconds 3
      }

      # Test if there was a list_/winget_error
      if (Test-Path -Path ('{0}\logs\error.txt' -f $WorkingDir) -ErrorAction SilentlyContinue) 
      {
         $MessageType = 'error'
         $Critical = Get-Content -Path ('{0}\logs\error.txt' -f $WorkingDir) -Raw
         $Critical = $Critical.Trim()
         $Critical = $Critical.Substring(0, [Math]::Min($Critical.Length, 50))
         $Message = ("Critical:`n{0}..." -f $Critical)
      }
      else 
      {
         $MessageType = 'success'
         $Message = $NotifLocale.local.outputs.output[9].message
      }
      Start-NotifTask -Message $Message -MessageType $MessageType -Button1Text $Button1Text -Button1Action $OnClickAction -ButtonDismiss -UserRun
   }
   catch 
   {
      # Check failed - Just send notification
      $Message = $NotifLocale.local.outputs.output[7].message
      $MessageType = 'error'
      Start-NotifTask -Message $Message -MessageType $MessageType -Button1Text $Button1Text -Button1Action $OnClickAction -ButtonDismiss -UserRun
   }
}
