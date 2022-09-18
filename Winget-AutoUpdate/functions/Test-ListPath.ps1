#Function to check Black/White List Path

function Test-ListPath ($ListPath, $UseWhiteList) {
    # UNC or Local Path
    if ($UseWhiteList){
        $ListType="included"
    }
    else {
        $ListType="excluded"
    }
    $Path = $ListPath
    $PathInfo=[System.Uri]$Path

    if($PathInfo.IsUnc){
        $PathType="UNC Path"
        $ListPath = -join($Path, "\", "$ListType", "_apps.txt")
        if(Test-Path -Path $ListPath -PathType leaf){
            Write-Output "Given path $Path type is $PathType and $ListPath is available..."
            }
        else {
            Write-Output "Given path $Path type is $PathType and $ListPath is not available..."
        }
    }
    elseif ($ListPath -like "http*"){
        $PathType="Web Path"
        $ListPath = -join($Path, "/", "$ListType", "_apps.txt")
        $wc = New-Object System.Net.WebClient
        try {
            $wc.OpenRead("$ListPath") | Out-Null
            Write-Output "Given path $Path type is $PathType and $ListPath is available..."
        } catch {
            Write-Output "Given path $Path type is $PathType and $ListPath is not available..."
        }
    }
    else {
        $PathType="Local Path"
        $ListPath = -join($Path, "\", "$ListType", "_apps.txt")
        if(Test-Path -Path $ListPath -PathType leaf){
            Write-Output "Given path $Path type is $PathType and $ListPath is available..."
            }
        else {
            Write-Output "Given path $Path type is $PathType and $ListPath is not available..."
        }
    }

}

# $WingetUpdatePath = "$env:ProgramData\Winget-AutoUpdate"
# $ListPath = "https://www.knifmelti.se"
# $UseWhiteList = $true
# #White List or Black List in share/online if differs
# if ($WingetUpdatePath -ne $ListPath){
#     Test-ListPath $ListPath $UseWhiteList
# }
