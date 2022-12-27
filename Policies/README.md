### Add the administrative template to an individual computer
1.  Copy the "**WAU.admx**" file to your Policy Definition template folder. (Example:  `C:\Windows\PolicyDefinitions`)
2.  Copy the "**WAU.adml**" file to the matching language folder in your Policy Definition folder. (Example:  `C:\Windows\PolicyDefinitions\en-US`)
 
### Add the administrative template to Active Directory
1.  On a domain controller or workstation with  [RSAT](https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/remote-server-administration-tools), go to the  **PolicyDefinition**  folder (also known as the  _Central Store_) on any domain controller for your domain.
2.  Copy the "**WAU.admx**" file to the PolicyDefinition folder. (Example:  `%systemroot%\sysvol\domain\policies\PolicyDefinitions`)
3.  Copy the "**WAU.adml**" file to the matching language folder in the PolicyDefinition folder. Create the folder if it doesn't already exist. (Example:  `%systemroot%\sysvol\domain\policies\PolicyDefinitions\EN-US`)
4.  If your domain has more than one domain controller, the new  [ADMX files](https://learn.microsoft.com/en-us/troubleshoot/windows-client/group-policy/create-and-manage-central-store)  will be replicated to them at the next domain replication interval.
