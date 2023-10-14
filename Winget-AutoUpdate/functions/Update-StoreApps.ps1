#Function to force an upgrade of Store Apps

Function Update-StoreApps ($Log = $false) {

	$force_string = "-> Forcing an upgrade of Store Apps (this can take a minute)..."
	$fail_string = "-> ...something went wrong!"

	#If not WSB or Server, upgrade Microsoft Store Apps!
	if (!(Test-Path "${env:SystemDrive}\Users\WDAGUtilityAccount") -and (Get-CimInstance Win32_OperatingSystem).Caption -notmatch "Windows Server") {
		switch ($Log) {
			$true {Write-ToLog $force_string "yellow"}
			Default {Write-Host $force_string -ForegroundColor Yellow}
		}
		try {
			$namespaceName = "root\cimv2\mdm\dmmap"
			$className = "MDM_EnterpriseModernAppManagement_AppManagement01"
			$wmiObj = Get-WmiObject -Namespace $namespaceName -Class $className
			$wmiObj.UpdateScanMethod() | Out-Null
			return $true
		}
		catch {
			switch ($Log) {
				$true {Write-ToLog $fail_string "red"}
				Default {Write-Host $fail_string -ForegroundColor Red}
			}
			return $false
		}
	}
}
