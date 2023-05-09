#Function to check if the mods directory is secured.
#Security: Mods directory must be protected (Users could create scripts of their own - then they'll run in System Context)!
#Check if Local Users have write rights in Mods directory or not (and take action if necessary):

function Invoke-ModsProtect ($ModsPath) {
    try {
        $directory = Get-Item -Path $ModsPath -ErrorAction SilentlyContinue
        $acl = Get-Acl -Path $directory.FullName
        #Local Users - S-1-5-32-545
        $userSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
        #Translate SID to Locale Name
        $ntAccount = $userSID.Translate([System.Security.Principal.NTAccount])
        $userName = $ntAccount.Value
        $userRights = [System.Security.AccessControl.FileSystemRights]"Write"

        $hasWriteAccess = $False

        foreach ($access in $acl.Access) {
            if ($access.IdentityReference.Value -eq $userName -and $access.FileSystemRights -eq $userRights) {
                $hasWriteAccess = $True
                break
            }
        }

        if ($hasWriteAccess) {
            #Disable inheritance
            $acl.SetAccessRuleProtection($True, $True)
            # Remove any existing rules
            $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
            #SYSTEM Full - S-1-5-18
            $userSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($userSID, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.SetAccessRule($rule)
            # Save the updated ACL
            Set-Acl -Path $directory.FullName -AclObject $acl

            #Administrators Full - S-1-5-32-544
            $acl = Get-Acl -Path $directory.FullName
            $userSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($userSID, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.SetAccessRule($rule)
            Set-Acl -Path $directory.FullName -AclObject $acl

            #Local Users ReadAndExecute - S-1-5-32-545 S-1-5-11
            $acl = Get-Acl -Path $directory.FullName
            $userSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($userSID, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.SetAccessRule($rule)
            Set-Acl -Path $directory.FullName -AclObject $acl

            #Authenticated Users ReadAndExecute - S-1-5-11
            $acl = Get-Acl -Path $directory.FullName
            $userSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11")
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($userSID, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.SetAccessRule($rule)
            Set-Acl -Path $directory.FullName -AclObject $acl

            return $True
        }
        return $False
    }
    catch {
        return "Error"
    }
}