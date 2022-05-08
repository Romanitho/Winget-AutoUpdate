#Function to configure prefered scope option as Machine
function Add-ScopeMachine ($path) {

    if (Test-Path $path){
        $ConfigFile = Get-Content -Path $path | Where-Object {$_ -notmatch '//'} | ConvertFrom-Json
    }
    if (!$ConfigFile){
        $ConfigFile = @{}
    }
    if ($ConfigFile.installBehavior.preferences.scope){
        $ConfigFile.installBehavior.preferences.scope = "Machine"
    }
    else {
        Add-Member -InputObject $ConfigFile -MemberType NoteProperty -Name 'installBehavior' -Value $(
            New-Object PSObject -Property $(@{preferences = $(
                    New-Object PSObject -Property $(@{scope = "Machine"}))
            })
        ) -Force
    }
    $ConfigFile | ConvertTo-Json | Out-File $path -Encoding utf8 -Force

}