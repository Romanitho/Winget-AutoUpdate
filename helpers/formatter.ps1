<#
    .description
        a simple example showing how to format a script automatically and - most importantly - in team collaboration, consistently
    .example
        powershell -File <PathOfThisFile> -SourceFile <PathOfFileToFormat>
#>

#Requires -Version 5
#Requires -Modules @{ ModuleName="PSScriptAnalyzer"; ModuleVersion="1.23.0" }

param(
    [string]$SourceFile
)
$File2 = $SourceFile.Replace('.ps1', '_formatted.ps1');
$ScriptDefinition = [System.IO.File]::ReadAllText($SourceFile);
$Settings = @{
    IncludeDefaultRules = $false
    IncludeRules = @(
        'PSAvoidTrailingWhitespace'
        'PSAvoidLongLines'
        'PSAvoidTrailingWhitespace'
        'PSPlaceOpenBrace'
        'PSPlaceCloseBrace'
        'UseCorrectCasing'
        'PSUseConsistentIndentation'
        'PSUseConsistentWhitespace'
    )
    Rules = @{
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $false
            NewLineAfter = $false
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace = @{
            Enable = $true
            NoEmptyLineBefore = $false
            IgnoreOneLineBlock = $true
            NewLineAfter = $true
        }
        PSUseConsistentIndentation = @{
            Enable = $true
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind = 'space'
        }
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $true
            CheckSeparator = $true
            CheckParameter = $true
            IgnoreAssignmentOperatorInsideHashTable = $false
        }
    }
}
[System.IO.File]::WriteAllText($File2, (Invoke-Formatter -ScriptDefinition $ScriptDefinition -Settings $Settings));
