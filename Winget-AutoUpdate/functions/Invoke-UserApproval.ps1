#Function to ask user consent before updating apps

function Invoke-UserApproval ($Apps){

    $WAUNotifApproved = "$WorkingDir/Config/NotifApproved.txt"
    $WAUNotifAppList = "$WorkingDir/Config/NotifAppList.csv"

    #Check for approved file
    if (Test-Path $WAUNotifApproved) {
        Write-ToLog  "-> User approved update notification."
        $AppListToUpdate = Import-Csv $WAUNotifAppList
        Remove-Item $WAUNotifApproved -Force -Confirm:$false
        Remove-Item $WAUNotifAppList -Force -Confirm:$false
    }
    #Otherwise generate AppList and send notif
    else {
        Write-ToLog "-> Creating AppList user must approve"
        $Apps | Export-Csv -Path $WAUNotifAppList -NoTypeInformation -Encoding UTF8

        if ($IsSystem) {
            $Button1Action = "wau:system"
            $OnClickAction = "wau:systemDialogBox"
        }
        else{
            $Button1Action = "wau:user"
            $OnClickAction = "wau:userDialogBox"
        }

        #Ask user to update apps

        $body = $Apps.Name | Out-String
        $Message = "Do you want to update these apps ?"
        $body += "`nPlease save your work and close theses apps"
        Start-NotifTask -Title "New available updates" -Message $Message -Body $body -ButtonDismiss -Button1Text "Yes" -Button1Action $Button1Action -OnClickAction $OnClickAction -MessageType "info"

        Write-ToLog "-> User approval requested. Waiting for user to approve available updates... Closing for now."
        #Closing job, waiting for user approval
        Exit 0
    }

}