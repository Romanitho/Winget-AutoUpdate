#Definition of return object
class IncludedApp {
    [string]$Value;
    [string]$Data;
    IncludedApp($v, $d) {
        $this.Value = $v;
        $this.Data = $d;
    }
}

#Function to get the allow List apps
function Get-IncludedApps {
    $AppIds = [System.Collections.Generic.List[IncludedApp]]::new();
    $WAU_GPORoot = "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate";
    #region whitelist in registry
    if ($GPOList)
    {
        $RegPath = "$WAU_GPORoot\WhiteList";
        if(Test-Path -Path $RegPath)
        {
            $RegKey = Get-Item -Path $RegPath;
            $values = $RegKey.Property
            $values | 
            ForEach-Object {
                $_v = $_;
                $_d = Get-ItemPropertyValue -Path $RegPath -Name $_
                $AppIds.Add([IncludedApp]::new($_v, $_d));
            }
        }
        return $AppIDs;
    }
    #endregion whitelist in registry

    #region whitelist pulled from URI
    elseif ($URIList) {
        $RegPath = "$WAU_GPORoot";
        $RegValueName = 'WAU_URIList';
        if(Test-Path -Path $RegPath)
        {
            $RegKey = Get-Item -Path $RegPath;
            $WAUURI = $RegKey.GetValue($RegValueName);
            if($WAUURI -ne $null)
            {
                $resp = Invoke-WebRequest -Uri $WAUURI -UseDefaultCredentials;
                if($resp.BaseResponse.StatusCode -eq [System.Net.HttpStatusCode]::OK)
                {
                    $resp.Content.Split([System.Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries) | 
                    ForEach-Object {
                        $AppIds.Add([IncludedApp]::new($AppIds.Count, $_));
                    }
                }
            }
        }
        return $AppIDs;
    }
    #endregion whitelist pulled from URI

    #region whitelist stored in own folder
    elseif (Test-Path "$WorkingDir\included_apps.txt") 
    {
        return (Get-Content -Path "$WorkingDir\included_apps.txt").Trim() | Where-Object { $_.length -gt 0 }

    }
    #endregion whitelist stored in own folder

    else
    #region empty whitelist (we need to return something..)
    {
        return [IncludedApp]::new([string]::Empty, [string]::Empty);
    }
    #endregion empty whitelist
}
