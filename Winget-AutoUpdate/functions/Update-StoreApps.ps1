#Function to force an upgrade of Store Apps

Function Update-StoreApps {

	$info_string = "-> Forcing an upgrade of Store Apps..."
	$action_string = "-> ...this can take a minute!"
	$fail_string = "-> ...something went wrong!"
	$irrelevant_string = "-> ...WAU is running on WSB (Windows Sandbox) or Windows Server - Microsoft Store is not available!"

	Write-ToLog $info_string "yellow"

	#If not WSB or Server, upgrade Microsoft Store Apps!
	if (!(Test-Path "${env:SystemDrive}\Users\WDAGUtilityAccount") -and (Get-CimInstance Win32_OperatingSystem).Caption -notmatch "Windows Server") {

		try {
			# Can't get it done with Get-CimInstance, using deprecated Get-WmiObject
			$namespaceName = "root\cimv2\mdm\dmmap"
			$className = "MDM_EnterpriseModernAppManagement_AppManagement01"
			$wmiObj = Get-WmiObject -Namespace $namespaceName -Class $className
			Write-ToLog $action_string "green"
			$wmiObj.UpdateScanMethod() | Out-Null
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
