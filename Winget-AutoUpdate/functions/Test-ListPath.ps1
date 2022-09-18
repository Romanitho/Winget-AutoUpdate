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
    $ListPath = -join($Path, "\", "$ListType", "_apps.txt")
    if($PathInfo.IsUnc){
        $PathType="UNC Path"
        if(Test-Path -Path $ListPath -PathType leaf){
            Write-Output "Given path $Path type is $PathType and $ListPath is available..."
            }
        else {
            Write-Output "Given path $Path type is $PathType and $ListPath is not available..."
        }
    }
    elseif ($ListPath -like "http"){
        $wc = New-Object System.Net.WebClient
        try {
            $wc.OpenRead('http://www.domain.com/test.csv') | Out-Null
            Write-Output 'File Exists'
        } catch {
            Write-Output 'Error / Not Found'
        }
    }
    else {
        $PathType="Local Path"
        if(Test-Path -Path $ListPath -PathType leaf){
            Write-Output "Given path $Path type is $PathType and $ListPath is available..."
            }
        else {
            Write-Output "Given path $Path type is $PathType and $ListPath is not available..."
        }
    }

}

$WingetUpdatePath = "$env:ProgramData\Winget-AutoUpdate"
$ListPath = "D:\Temp"
$UseWhiteList = $true
#White List or Black List in share/online if differs
if ($WingetUpdatePath -ne $ListPath){
    Test-ListPath $ListPath $UseWhiteList
}
