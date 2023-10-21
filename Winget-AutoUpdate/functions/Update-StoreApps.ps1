#Function to force an upgrade of Store Apps

Function Update-StoreApps {

	$force_string = "-> Forcing an upgrade of Store Apps (this can take a minute)..."
	$fail_string = "-> ...something went wrong!"
	$notrelevant_string = "-> WAU is running on a WSB (Windows Sandbox) or a Windows Server - Microsoft Store is not available!"

	#If not WSB or Server, upgrade Microsoft Store Apps!
	if (!(Test-Path "${env:SystemDrive}\Users\WDAGUtilityAccount") -and (Get-CimInstance Win32_OperatingSystem).Caption -notmatch "Windows Server") {

		Write-ToLog $force_string "yellow"

		try {
			# Can't get it done with Get-CimInstance, using deprecated Get-WmiObject
			$namespaceName = "root\cimv2\mdm\dmmap"
			$className = "MDM_EnterpriseModernAppManagement_AppManagement01"
			$wmiObj = Get-WmiObject -Namespace $namespaceName -Class $className
			$wmiObj.UpdateScanMethod() | Out-Null
			return $true
		}
		catch {
			Write-ToLog $fail_string "red"
			return $false
		}
	}
	else {
		Write-ToLog $notrelevant_string "yellow"
	}
}
