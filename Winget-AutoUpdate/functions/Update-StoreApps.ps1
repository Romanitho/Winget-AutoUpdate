#Function to force an upgrade of Store Apps

Function Update-StoreApps ($Log = $false) {

	#If not WSB or Server, upgrade Microsoft Store Apps!
	if (!(Test-Path "${env:SystemDrive}\Users\WDAGUtilityAccount") -and (Get-CimInstance Win32_OperatingSystem).Caption -notmatch "Windows Server") {
		switch ($Log) {
			$true {Write-ToLog "-> Forcing an upgrade of Store Apps (this can take a minute)..." "yellow"}
			Default {Write-Host "-> Forcing an upgrade of Store Apps (this can take a minute)..." -ForegroundColor Yellow}
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
				$true {Write-ToLog "-> ...something went wrong!" "red"}
				Default {Write-Host "-> ...something went wrong!" -ForegroundColor Red}
			}
			return $false
		}
	}
}
