# WAU Administration Template

In an enterprise environment, it's crucial that different groups can have different settings in applications or implement other mandatory settings for security/management reasons. **WAU** doesn't have any settings that can be changed except during installation (or by editing the registry/the `Winget-AutoUpdate` task as **Admin**). However, with the use of **ADML/ADMX** files, you can manage every **WAU** setting from within **GPO** or **Intune policies**.

![image](https://user-images.githubusercontent.com/102996177/213920242-7ff8e2b4-d926-4407-b860-1e5922e29c3e.png)

## Administrative Template

### To an Individual Computer
1. Copy the **`WAU.admx`** file to your Policy Definitions template folder.  
   Example: `C:\Windows\PolicyDefinitions`
2. Copy the **`WAU.adml`** file to the matching language folder in your Policy Definitions folder.  
   Example: `C:\Windows\PolicyDefinitions\en-US`

### To Active Directory
1. On a domain controller or workstation with [RSAT](https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/remote-server-administration-tools), go to the **PolicyDefinitions** folder (also known as the _Central Store_) on any domain controller for your domain.
2. Copy the **`WAU.admx`** file to the PolicyDefinitions folder.  
   Example: `%systemroot%\sysvol\domain\policies\PolicyDefinitions`
3. Copy the **`WAU.adml`** file to the matching language folder in the PolicyDefinitions folder. Create the folder if it doesn't already exist.  
   Example: `%systemroot%\sysvol\domain\policies\PolicyDefinitions\en-US`
4. If your domain has more than one domain controller, the new [ADMX files](https://learn.microsoft.com/en-us/troubleshoot/windows-client/group-policy/create-and-manage-central-store) will be replicated to them at the next domain replication interval.

## Intune

Please follow the comprehensive Microsoft documentation to import and manage the WAU policies:  
[Import and Manage Administrative Templates in Intune](https://learn.microsoft.com/en-us/mem/intune-service/configuration/administrative-templates-import-custom#add-the-admx-and-adml-files)

## Important Notes

- When using GPO or Intune policies, you need to enable `Activate WAU GPO Management` for the policies to work. This setting is not intuitive and should be part of any decommissioning considerations.
- This project only supports the `en-US` ADML file.
