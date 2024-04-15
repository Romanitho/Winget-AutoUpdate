# Obtain UTC offset (think about moving it to the parent method)
    $DateTime = New-Object -ComObject 'WbemScripting.SWbemDateTime';
    $DateTime.SetVarDate($(Get-Date));
    $UtcValue = $DateTime.Value;
    $global:CMTraceLog_UtcOffset = $UtcValue.Substring(21, $UtcValue.Length - 21);
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($DateTime) | Out-Null;

# Set context of process which writes a message
    $global:CMTraceLog_Context = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name;

# set string templates for formatting later
[string]$global:logline_part1_template_nonerror = "<![LOG[{0}: {1}]LOG]!>";
[string]$global:logline_part1_template_error    = "<![LOG[{0}: {1}`r`r`nCommand: {2}`nScriptName: {3}`nLine Number: {4}`nColumn Number: {5}`nLine: {6}]LOG]!>";
[string]$global:logline_part2_template = "<time=`"{0}{1}`" date=`"{2}`" component=`"{3}`" context=`"{4}`" type=`"{5}`" thread=`"{6}`" file=`"{7}`">";

# (full help at the end of file)

enum CMTraceLogSeverity
{
           Warning = 2
             Error = 3
           Verbose = 4
             Debug = 5
       Information = 6
}

Function Write-CMTraceLog
{
    # Define and validate parameters 
    [CmdletBinding()] 
    Param( 

        #Path to the log file 
        [parameter(Mandatory=$False)]
        [String]$Logfile = "$Script:WorkingDir\logs\updates.log",
         
        #The information to log
        [parameter(Mandatory=$True)]
        $Message,
 
        #The severity (Error, Warning, Verbose, Debug, Information)
        [parameter(Mandatory=$True)]
        [ValidateSet('Warning','Error','Verbose','Debug', 'Information', IgnoreCase=$True)]
        [String]$Type,

        #Write back to the console or just to the log file. By default it will write back to the host.
        [parameter(Mandatory=$False)]
        [switch]$WriteBackToHost = $False

    )#Param

    # Get the info about the calling script, function etc
    $callinginfo = (Get-PSCallStack)[1];

    # Set Source Information
    $Source = (Get-PSCallStack)[1].Location;

    # Set Component Information
    $Component = (Get-Process -Id $PID).ProcessName;

    # Set PID Information
    $ProcessID = $PID;

    # Set date/time of message
    $dt = Get-Date;
    [string]$time = [string]::Format("{0:HH:mm:ss.fff}", $dt);
    [string]$date = [string]::Format("{0:MM-dd-yyyy}", $dt);

    # Set the order 
    <#
    switch($Type)
    {
           'Warning' {$Severity = 2;} #Warning
             'Error' {$Severity = 3;} #Error
           'Verbose' {$Severity = 4;} #Verbose
             'Debug' {$Severity = 5;} #Debug
       'Information' {$Severity = 6;} #Information
    }
    #>
    $severity = [int]([CMTraceLogSeverity]::$Type);

    #region set the 1st part of logged entry (templates for formatting)
        if($Type -eq 'Error')
        {
            if($Message.exception.Message)
            {
                # cool! we have an exception, we can use it
            }
            else
            {
                # we do not have an exception, we need to prepare out own custom error to use later
                [System.Exception]$Exception = $Message;
                [String]$ErrorID = 'Custom Error';
                [System.Management.Automation.ErrorCategory]$ErrorCategory = [Management.Automation.ErrorCategory]::WriteError;
                $ErrorRecord = [System.Management.Automation.ErrorRecord]::new($Exception, $ErrorID, $ErrorCategory, $Message);
                $Message = $ErrorRecord;
            }
            [string]$logline_part1 = [string]::Format(
                $global:logline_part1_template_error,
                $Type.ToUpper(),
                $Message.exception.message,
                $Message.InvocationInfo.MyCommand,
                $Message.InvocationInfo.ScriptName,
                $Message.InvocationInfo.ScriptLineNumber,
                $Message.InvocationInfo.OffsetInLine,
                $Message.InvocationInfo.Line
            );
        }
        else
        {
            [string]$logline_part1 = [string]::Format($global:logline_part1_template_nonerror, $Type.ToUpper(), $message);
        }
    #endregion set the 1st part of logged entry (templates for formatting)

    #region set the 2nd part of logged entry
        [string]$logline_part2 = [string]::Format(
            $global:logline_part2_template,
            $time,
            $global:CMTraceLog_UtcOffset,
            $date,
            $Component,
            $global:CMTraceLog_Context,
            $Severity,
            $ProcessID,
            $Source
            );
    #endregion set the 2nd part of logged entry

    #region Switch statement to write out to the log and/or back to the host.

    # Write the log entry in the CMTrace Format.
    $logline = $logline_part1 + $logline_part2;
    $logline | Out-File -Append -Encoding utf8 -FilePath $Logfile;

    switch ($severity)
    {
    #region Warning
        2{
            #Write back to the host if $Writebacktohost is true.
            if(($WriteBackToHost))
            {
                Switch($PSCmdlet.GetVariableValue('WarningPreference')){
                    'Continue' {$WarningPreference = 'Continue';Write-Warning -Message "$Message";$WarningPreference=''}
                    'Stop' {$WarningPreference = 'Stop';Write-Warning -Message "$Message";$WarningPreference=''}
                    'Inquire' {$WarningPreference ='Inquire';Write-Warning -Message "$Message";$WarningPreference=''}
                    'SilentlyContinue' {}
                }
            }
        }
    #endregion Warning

    #region Error
        3{
            #This if statement is to catch the two different types of errors that may come through. A normal terminating exception will have all the information that is needed, if it's a user generated error by using Write-Error,
            #then the else statement will setup all the information we would like to log.

            #Write back to the host if $Writebacktohost is true.
            if(($WriteBackToHost))
            {
                #Write back to Host
                Switch($PSCmdlet.GetVariableValue('ErrorActionPreference'))
                {
                    'Stop'{$ErrorActionPreference = 'Stop';$Host.Ui.WriteErrorLine("ERROR: $([String]$Message.Exception.Message)");Write-Error $Message -ErrorAction 'Stop';$ErrorActionPreference=''}
                    'Inquire'{$ErrorActionPreference = 'Inquire';$Host.Ui.WriteErrorLine("ERROR: $([String]$Message.Exception.Message)");Write-Error $Message -ErrorAction 'Inquire';$ErrorActionPreference=''}
                    'Continue'{$ErrorActionPreference = 'Continue';$Host.Ui.WriteErrorLine("ERROR: $([String]$Message.Exception.Message)");$ErrorActionPreference=''}
                    'Suspend'{$ErrorActionPreference = 'Suspend';$Host.Ui.WriteErrorLine("ERROR: $([String]$Message.Exception.Message)");Write-Error $Message -ErrorAction 'Suspend';$ErrorActionPreference=''}
                    'SilentlyContinue'{}
                }

            }
        }
    #endregion Error

    #region Verbose
        4{
            #Write back to the host if $Writebacktohost is true.
            if(($WriteBackToHost)){
                Switch ($PSCmdlet.GetVariableValue('VerbosePreference')) {
                    'Continue' {$VerbosePreference = 'Continue'; Write-Verbose -Message "$Message";$VerbosePreference = ''}
                    'Inquire' {$VerbosePreference = 'Inquire'; Write-Verbose -Message "$Message";$VerbosePreference = ''}
                    'Stop' {$VerbosePreference = 'Stop'; Write-Verbose -Message "$Message";$VerbosePreference = ''}
                }
            }
        }
    #endregion Verbose

    #region Debug
        5{
            #Write back to the host if $Writebacktohost is true.
            if(($WriteBackToHost))
            {
                Switch ($PSCmdlet.GetVariableValue('DebugPreference')){
                    'Continue' {$DebugPreference = 'Continue'; Write-Debug -Message "$Message";$DebugPreference = ''}
                    'Inquire' {$DebugPreference = 'Inquire'; Write-Debug -Message "$Message";$DebugPreference = ''}
                    'Stop' {$DebugPreference = 'Stop'; Write-Debug -Message "$Message";$DebugPreference = ''}
                }
            }
        }
    #endregion Debug

    #region Information
        6{
            #Write back to the host if $Writebacktohost is true. 
            if(($WriteBackToHost)){
                Switch ($PSCmdlet.GetVariableValue('InformationPreference')){
                    'Continue' {$InformationPreference = [System.Management.Automation.ActionPreference]::Continue; Write-Information "INFORMATION: $Message" -InformationAction Continue ; $InformationPreference = ''}
                    'Inquire' {$InformationPreference = [System.Management.Automation.ActionPreference]::Inquire;   Write-Information "INFORMATION: $Message" -InformationAction Inquire;   $InformationPreference = ''}
                    'Stop' {$InformationPreference = [System.Management.Automation.ActionPreference]::Stop;         Write-Information "INFORMATION: $Message" -InformationAction Stop;      $InformationPreference = ''}
                    'Suspend' {$InformationPreference = [System.Management.Automation.ActionPreference]::Suspend;   Write-Information "INFORMATION: $Message" -InformationAction Suspend;   $InformationPreference = ''}
                }
            }
        }
    #endregion Information

    }
    #endregion Switch statement to write out to the log and/or back to the host.
}

<# 
.SYNOPSIS 
   Write to a log file in a format that takes advantage of the CMTrace.exe log viewer that comes with SCCM.
   Found @ https://wolffhaven.gitlab.io/wolffhaven_icarus_test/powershell/write-cmtracelog-dropping-logs-like-a-boss/
   heavily modified for the purpose of WAU project
 
.DESCRIPTION 
   Output strings to a log file that is formatted for use with CMTRace.exe and also writes back to the host.
 
   The severity of the logged line can be set as: 
 
        2-Error
        3-Warning
        4-Verbose
        5-Debug
        6-Information

 
   Warnings will be highlighted in yellow. Errors are highlighted in red. 
 
   The tools to view the log: 
 
   SMS Trace - http://www.microsoft.com/en-us/download/details.aspx?id=18153 
   CM Trace - https://www.microsoft.com/en-us/download/details.aspx?id=50012 or the Installation directory on Configuration Manager 2012 Site Server - <Install Directory>\tools\ 

   With current atomization of the code, the component parameter should be passed as one of parameters 
   [string]$component_name = (Get-PSCallStack)[0].FunctionName
   If logger function is not called in the function, then we could designate a decriptive name for it.
 
.EXAMPLE 
Try{
    Get-Process -Name DoesnotExist -ea stop
}
Catch{
    Write-CMTraceLog -Logfile "C:\output\logfile.log -Message $Error[0] -Type Error
}
 
   This will write a line to the logfile.log file in c:\output\logfile.log. It will state the errordetails in the log file 
   and highlight the line in Red. It will also write back to the host in a friendlier red on black message than
   the normal error record.
 
.EXAMPLE
 $VerbosePreference = Continue
 Write-CMTraceLog -Message "This is a verbose message." -Type Verbose

   This example will write a verbose entry into the log file and also write back to the host. The Write-CMTraceLog will obey
   the preference variables.

.EXAMPLE
Write-CMTraceLog -Message "This is an informational message" -Type Information -WritebacktoHost:$false

    This example will write the informational message to the log but not back to the host.

.EXAMPLE
Function Test{
    [cmdletbinding()]
    Param()
    Write-CMTraceLog -Message "This is a verbose message" -Type Verbose
}
Test -Verbose

This example shows how to use write-cmtracelog inside a function and then call the function with the -verbose switch.
The write-cmtracelog function will then print the verbose message.

.NOTES
    
    ##########
    Change Log
    ##########
    
    v1.6 - 2024-04-01 - reorganized com handling triggered by UTC Offset calculation, reduced the parallelism by moving err/non-err strings generation to the front

    ##########
    
    v1.5 - 2015-03-12 - Found bug with Error writing back to host twice. Fixed.

    ##########
    
    v1.4 - 2015-03-12 - Found bug with Warning writebackto host duplicating warning error message.
                        Fixed.

    ##########
    
    v1.3 - 2015-02-23 - Commented out line 224 and 249 as it was causing a duplicaton of the message.

    ##########

    v1.2 - Fixed inheritance of preference variables from child scopes finally!! Changed from using
            using get-variable -scope 1 (which doesn't work when a script modules calls a function:
            See this Microsoft Connect bug https://connect.microsoft.com/PowerShell/feedback/details/1606119.)
            Anyway now now i use the $PSCmdlet.GetVariableValue('VerbosePreference') command and it works.
    
    ##########

    v1.1 - Found a bug with the get-variable scope. Need to refer to 2 parent scopes for the writebacktohost to work.
         - Changed all Get-Variable commands to use Scope 2, instead of Scope 1.

    ##########

    v1.0 - Script Created
#>
