#Function to force an upgrade of Store Apps
Function Get-StoreApps {

    try {
        $namespaceName = "root\cimv2\mdm\dmmap"
        $className = "MDM_EnterpriseModernAppManagement_AppManagement01"
        $wmiObj = Get-WmiObject -Namespace $namespaceName -Class $className
        $wmiObj.UpdateScanMethod()
        return $true
    }
    catch {
        return $false
    }
}
