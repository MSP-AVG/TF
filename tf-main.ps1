<#
Loads Functions
Creates Setup Complete Files
#>

Set-ExecutionPolicy Bypass -Force

# Load functions
iex (irm https://raw.githubusercontent.com/MSP-AVG/TF/refs/heads/main/tf-ap-menu.ps1)
Write-Host -Foreground Red $GroupTag
Start-Sleep -Seconds 3
iex (irm https://raw.githubusercontent.com/MSP-AVG/TF/refs/heads/main/tf-functions.ps1)

# Ensure execution policy
Set-ExecutionPolicy Bypass -Force

# Proceed only in WinPE
if ($env:SystemDrive -eq 'X:') {

    # Define Windows settings
    $Product = Get-MyComputerProduct
    $OSVersion = 'Windows 11'
    $OSReleaseID = '24H2'
    $OSName = 'Windows 11 24H2 x64'
    $OSEdition = 'Enterprise'
    $OSActivation = 'Volume'
    $OSLanguage = 'en-US'

    $Global:MyOSDCloud = [ordered]@{
        Restart = $false
        RecoveryPartition = $true
        OEMActivation = $true
        WindowsUpdate = $true
        WindowsUpdateDrivers = $true
        WindowsDefenderUpdate = $true
        SetTimeZone = $true
        ClearDiskConfirm = $false
        ShutdownSetupComplete = $true
        SyncMSUpCatDriverUSB = $true
    }

    # Get driver pack
    $DriverPack = Get-OSDCloudDriverPack -Product $Product -OSVersion $OSVersion -OSReleaseID $OSReleaseID
    if ($DriverPack) {
        $Global:MyOSDCloud.DriverPackName = $DriverPack.Name
    }

    # Output config
    Write-Output $Global:MyOSDCloud

    # Import latest module
    $ModulePath = (Get-ChildItem -Path "$($Env:ProgramFiles)\WindowsPowerShell\Modules\osd" | Where-Object {$_.Attributes -match "Directory"} | Select-Object -Last 1).FullName
    Import-Module "$ModulePath\OSD.psd1" -Force

    # Launch OSDCloud
    Write-Host "Starting OSDCloud" -ForegroundColor Green
    Write-Host "Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage"
    Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage

    Write-Host "OSDCloud Process Complete, Running Custom Actions From Script Before Reboot" -ForegroundColor Green

    # Copy CMTrace
    if (Test-Path "x:\windows\system32\cmtrace.exe") {
        Copy-Item "x:\windows\system32\cmtrace.exe" -Destination "C:\Windows\System\cmtrace.exe"
    }

    # Save group tag
    $GroupTag | Out-File -FilePath C:\Windows\DeviceType.txt

    # SetupComplete script
    Set-SetupCompleteOSDCloudUSB

    # Save ESD image back to USB
    $OSDCloudUSB = Get-Volume.usb | Where-Object {($_.FileSystemLabel -match 'OSDCloud') -or ($_.FileSystemLabel -match 'BHIMAGE')} | Select-Object -First 1
    $DriverPath = "$($OSDCloudUSB.DriveLetter):\OSDCloud\OS\"
    $ImageFileName = Get-ChildItem -Path $DriverPath -Name *.esd -ErrorAction SilentlyContinue
    $ImageFileNameDL = Get-ChildItem -Path 'C:\OSDCloud\OS' -Name *.esd -ErrorAction SilentlyContinue
    if (!(Test-Path $DriverPath)) { New-Item -ItemType Directory -Path $DriverPath | Out-Null }

    if ($ImageFileName -ne $ImageFileNameDL) {
        Remove-Item -Path "$DriverPath$ImageFileName" -Force -ErrorAction SilentlyContinue
        if (!(Test-Path "$DriverPath$ImageFileNameDL")) {
            Copy-Item -Path "C:\OSDCloud\OS\$ImageFileNameDL" -Destination "$DriverPath$ImageFileNameDL" -Force
        }
    }

    # ================================
    # Set input locale & inject unattend.xml
    # ================================
    switch ($GroupTag) {
        'TF-BE' { $InputLocale = '0813:00000813'; $SystemLocale = 'nl-BE'; $UserLocale = 'nl-BE' }
        'TF-BE-Shared' { $InputLocale = '0813:00000813'; $SystemLocale = 'nl-BE'; $UserLocale = 'nl-BE' }
        'TF-LU' { $InputLocale = '046E:0000046E'; $SystemLocale = 'lb-LU'; $UserLocale = 'lb-LU' }
        'TF-DE' { $InputLocale = '0407:00000407'; $SystemLocale = 'de-DE'; $UserLocale = 'de-DE' }
        'TF-NL' { $InputLocale = '0413:00020409'; $SystemLocale = 'nl-NL'; $UserLocale = 'nl-NL' }
        'TF-NL-Shared' { $InputLocale = '0413:00020409'; $SystemLocale = 'nl-NL'; $UserLocale = 'nl-NL' }
        default {
            $InputLocale = '0409:00000409'; $SystemLocale = 'en-US'; $UserLocale = 'en-US'
        }
    }

    # Apply with DISM
    Dism /image:C:\ /Set-InputLocale:$InputLocale
    Dism /image:C:\ /Set-UserLocale:$UserLocale
    Dism /image:C:\ /Set-SysLocale:$SystemLocale
    Dism /image:C:\ /Set-UILang:$OSLanguage
    Dism /image:C:\ /Set-AllIntl:$InputLocale

    # Write unattend.xml
    $UnattendPath = "C:\Windows\Panther\Unattend\Unattend.xml"
    $UnattendContent = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <InputLocale>$InputLocale</InputLocale>
      <SystemLocale>$SystemLocale</SystemLocale>
      <UILanguage>$OSLanguage</UILanguage>
      <UserLocale>$UserLocale</UserLocale>
    </component>
  </settings>
</unattend>
"@
    New-Item -Path (Split-Path $UnattendPath) -ItemType Directory -Force | Out-Null
    $UnattendContent | Set-Content -Path $UnattendPath -Encoding UTF8

    # Restart
    Restart-Computer
}
