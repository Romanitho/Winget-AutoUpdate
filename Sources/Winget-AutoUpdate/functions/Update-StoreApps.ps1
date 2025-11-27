<#
.SYNOPSIS
    Triggers an update scan for Microsoft Store applications.

.DESCRIPTION
    Uses MDM (Mobile Device Management) API to force a scan for
    Microsoft Store app updates. This is useful as a fallback when
    WinGet MSIXBundle installation fails.

.OUTPUTS
    Boolean: True on success, False on failure.

.EXAMPLE
    Update-StoreApps

.NOTES
    Not available on Windows Server or Windows Sandbox (WSB).
    Uses MDM_EnterpriseModernAppManagement WMI class.
#>
Function Update-StoreApps {

    $info_string = "-> Forcing an upgrade of Store Apps..."
    $action_string = "-> ...this can take a minute!"
    $fail_string = "-> ...something went wrong!"
    $irrelevant_string = "-> ...WAU is running on WSB (Windows Sandbox) or Windows Server - Microsoft Store is not available!"

    Write-ToLog $info_string "yellow"

    # Check if running on Windows Sandbox or Windows Server (Store not available)
    if (!(Test-Path "${env:SystemDrive}\Users\WDAGUtilityAccount") -and (Get-CimInstance Win32_OperatingSystem).Caption -notmatch "Windows Server") {

        try {
            # Use MDM WMI class to trigger store app update scan
            $namespaceName = "root\cimv2\mdm\dmmap"
            $className = "MDM_EnterpriseModernAppManagement_AppManagement01"
            $methodName = 'UpdateScanMethod'
            $cimObj = Get-CimInstance -Namespace $namespaceName -ClassName $className -Shallow

            Write-ToLog $action_string "green"
            $result = $cimObj | Invoke-CimMethod -MethodName $methodName

            if ($result.ReturnValue -ne 0) {
                Write-ToLog $fail_string "red"
                return $false
            }
            return $true
        }
        catch {
            Write-ToLog $fail_string "red"
            return $false
        }
    }
    else {
        Write-ToLog $irrelevant_string "yellow"
    }
}
