#Function to check Black/White List Path

function Test-ListPath ($ListPath, $UseWhiteList) {
    # UNC, Web or Local Path
    if ($UseWhiteList){
        $ListType="included"
    }
    else {
        $ListType="excluded"
    }
    $LocalList = -join($WingetUpdatePath, "\", $ListType, "_apps.txt")
    $ExternalList = $ListPath
    $PathInfo=[System.Uri]$ListPath

    if($PathInfo.IsUnc){
        $PathType="UNC Path"
        $ExternalList = -join($ListPath, "\", $ListType, "_apps.txt")
        if(Test-Path -Path $ExternalList -PathType leaf){
            Write-Output "Given path $ListPath type is $PathType and $ExternalList is available..."

            $dateLocal = (Get-Item "$LocalList").LastWriteTime 
            $dateExternal = (Get-Item "$ListPath").LastWriteTime
            if ($dateExternal -gt $dateLocal) {
                Write-Host("$ExternalList was modified after $LocalList")
            }
        }
        else {
            Write-Output "Given path $ListPath type is $PathType and $ExternalList is not available..."
        }
    }
    elseif ($ListPath -like "http*"){
        $PathType="Web Path"
        $ExternalList = -join($ListPath, "/", $ListType, "_apps.txt")
        $wc = New-Object System.Net.WebClient
        try {
            $wc.OpenRead("$ExternalList") | Out-Null
            Write-Output "Given path $ListPath type is $PathType and $ExternalList is available..."
        }
        catch {
            Write-Output "Given path $ListPath type is $PathType and $ExternalList is not available..."
        }
    }
    else {
        $PathType="Local Path"
        $ExternalList = -join($ListPath, "\", $ListType, "_apps.txt")
        if(Test-Path -Path $ExternalList -PathType leaf){
            Write-Output "Given path $ListPath type is $PathType and $ExternalList is available..."

            $dateLocal = (Get-Item "$LocalList").LastWriteTime 
            $dateExternal = (Get-Item "$ListPath").LastWriteTime
            if ($dateExternal -gt $dateLocal) {
                Write-Host("$ExternalList was modified after $LocalList")
            }
        }
        else {
            Write-Output "Given path $ListPath type is $PathType and $ExternalList is not available..."
        }
    }
}

$WingetUpdatePath = "$env:ProgramData\Winget-AutoUpdate"
$ListPath = "D:\Temp"
$UseWhiteList = $false
#White List or Black List in share/online if differs
if ($WingetUpdatePath -ne $ListPath){
    Test-ListPath $ListPath $UseWhiteList
}
