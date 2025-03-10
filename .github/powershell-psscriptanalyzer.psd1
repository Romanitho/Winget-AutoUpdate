#Documentation: https://github.com/PowerShell/PSScriptAnalyzer/blob/master/docs/markdown/Invoke-ScriptAnalyzer.md#-settings
@{
    ExcludeRules = @(
        'PSMissingModuleManifestField',
        'PSUseLiteralInitializerForHashtable',
        'MissingPropertyName'
        'PSAvoidGlobalVars',
        'PSAvoidUsingPositionalParameters',
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingEmptyCatchBlock',
        'PSPossibleIncorrectComparisonWithNull',
        'PSAvoidTrailingWhitespace',
        'PSUseApprovedVerbs',
        'PSAvoidUsingWMICmdlet',
        'PSReviewUnusedParameter',
        'PSUseDeclaredVarsMoreThanAssignment',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseDeclaredVarsMoreThanAssignments'
    )
}
