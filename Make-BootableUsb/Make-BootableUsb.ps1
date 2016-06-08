Param(
    [ValidateScript({Test-Path $_})]
    [string]$imageFolder
)

$TargetDiskCharacter = New-Object PSObject -Property @{
    Size = '29 GB'
    Type = 'USB'
}  

$AllDisks          = @() 
$AllDiskDetails    = @()  
$TargetDiskDetails = @()     

function IsAdminElevated{
    $isAdminAccessToken = $true
    Write-Host "Checking Administrator credentials" 
    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { 
        Write-Warning "You are not running this as an Administrator!`nPlease re-run this with an Administrator account." 
        $isAdminAccessToken = $false
    }
    else{
        Write-Host "You are running as Administrator."
    }

    $isAdminAccessToken
}

function Invoke-DiskPart($command){
    $tempFile = Join-Path $env:TEMP "$(Get-Random).txt"
    $command | Out-File -FilePath $tempFile -Encoding utf8

    $process = New-Object System.Diagnostics.Process

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "diskpart"
    $startInfo.Arguments = "/s $tempFile"
    $startInfo.RedirectStandardOutput = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true

    $process.StartInfo = $startInfo
    $process.Start() | Out-Null
    $process.WaitForExit()
     
    if($process.ExitCode -eq 0){
        $result = $process.StandardOutput.ReadToEnd() -split "`n" | % { $_.ToString().Trim() } | ? { $_ }
        $lastIndex = $result.Length - 1
        $result = $result[5..$lastIndex]
    }

    Remove-Item $tempFile -Force
    $result
}

function Get-AllDisks{
    if($AllDisks.Count -eq 0){
        $diskInfo = Invoke-DiskPart "list disk"
        $AllDisks = $diskInfo | % {
            $di = $_ -split '  ' | % { $_.tostring().trim() } | ? {$_}
            New-Object PSObject -Property @{
                DiskNum    = $di[0]
                DiskStatus = $di[1]
                DiskSize   = $di[2]
            }
        }

        Write-Host "*** All Disk List"
        Write-Host "$AllDisks"
    }

    $AllDisks
}

function Get-AllDiskDetails{
    if($AllDiskDetails.Count -eq 0){
        $disks = Get-AllDisks
        $AllDiskDetails = $disks | % {
            $diskNum = $_.DiskNum 
            $detail = Invoke-DiskPart @("select $diskNum", "detail disk") 
            $lastIndex = $detail.Length - 1 
            $type = $detail | ? {$_.StartsWith('Type   :')}
            $volLtr = $detail[16..$lastIndex] | % {$_[13]} | ? {$_.tostring().trim()}
            $type = ($type -replace 'Type   :', '').Trim() 
            $_ | Add-Member -MemberType NoteProperty -Name Type -Value $type
            $_ | Add-Member -MemberType NoteProperty -Name VolLtr -Value $volLtr
            $_
        }

        Write-Host "*** All Disk Details"
        Write-Host $AllDiskDetails
    }
    
    $AllDiskDetails
}

function Get-TargetDiskDetails{
    if($TargetDiskDetails.Count -eq 0){
        $diskList = Get-AllDiskDetails
        $TargetDiskDetails = $diskList | ? { $_.Type -eq $TargetDiskCharacter.Type -and $_.DiskSize -eq $TargetDiskCharacter.Size } 

        Write-Host "*** Target Disk Details"
        Write-Host $TargetDiskDetails
    }

    $TargetDiskDetails
}

function Active-TargetDisks{
    Get-TargetDiskDetails | % {
        $commands = @(
            "list disk"
            "select $($_.DiskNum)"
            "clean"
            "create partition primary"
            "format fs=ntfs quick"
            "active"
            "online"
        )

        Write-Host "Start to active target disks..."
        Invoke-DiskPart $commands
    }
}

function Copy-ImageFolder($imgFolder){
    $volLtrs = Get-TargetDiskDetails | % { "$($_.VolLtr):" }

    Write-Host "Start to copy image folder to target volume..."
    Write-Host $volLtrs
    $volLtrs | % { robocopy $imageFolder $_ /E }
}

function Make-BootableUsb{
    if(-not (IsAdminElevated)){
        exit -1
    }

    Active-TargetDisks
    Copy-ImageFolder $imageFolder
}

Make-BootableUsb
Write-Host "Complete making bootable usb!"
