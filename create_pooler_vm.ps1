$ErrorActionPreference = 'Stop'
$thisDir = $PSScriptRoot

Add-Type -AssemblyName System.IO.Compression.FileSystem

# http://int-resources.ops.puppetlabs.net/ISO/Windows/2016TP5Pre-Build-14300.1000.160324-1723.RS1/
# Latest Windows VMWare Tools https://packages.vmware.com/tools/esx/latest/windows/x64/index.html
# SetRights - https://github.com/cloudbase/SetUserAccountRights/releases/download/1.0/SetUserAccountRights.exe 

$targetPath = "C:\dev\transfer\nano.vmdk" #"$thisDir\nano.vmdk"
$AdministratorPassword = ConvertTo-SecureString -AsPlaintext -Force "Qu@lity!"
$tmpDir = "$thisDir\temp"
$tempExtraFiles = "$tmpDir\ExtraFiles"
$sourcesDir = "$thisDir\Sources"

# Cleanup
if (Test-Path -Path $tmpDir) {
  Write-Host "Removing temp..."
  Remove-Item -Path $tmpDir -Recurse -Force -Confirm:$false | Out-Null
}
New-Item -Path $tmpDir -ItemType Directory | Out-Null
if (Test-Path -path $targetPath) { Remove-Item -Path $targetPath -Force -Confirm:$false | Out-Null }
if (-not (Test-Path -Path $sourcesDir)) { New-Item -Path "$thisDir\Sources" -ItemType Directory | Out-Null }

# Grab the required sources...
#   Grab SetUserAccountRights
$SetRightsEXE = "$sourcesDir\setuser\SetUserAccountRights.exe"
if (-not (Test-Path -Path $SetRightsEXE)) {
  if (-not (Test-Path -Path "$sourcesDir\setuser")) { New-Item -Path "$sourcesDir\setuser" -ItemType Directory | Out-Null }
  Write-Host "Downloading SetUserAccountRights.exe..."  
  $url64bit = 'https://github.com/cloudbase/SetUserAccountRights/releases/download/1.0/SetUserAccountRights.exe'
  (New-Object System.Net.WebClient).DownloadFile($url64bit, $SetRightsEXE) | Out-Null
}
#  Grab VMWare Tools
$VMwareToolsISOPath = "$sourcesDir\VMware-tools.iso"
if (-not (Test-Path -Path $VMwareToolsISOPath)) {
  Write-Host "Getting list of VMWare tools to download..."
  $rootURL = 'https://packages.vmware.com/tools/esx/latest/windows/x64/'
  $url64bit = ''
  # Web Scrape the Vmware Tools download site...
  $response = Invoke-WebRequest -Uri $rootURL -UseBasicParsing

  $url64bit = $response.Links | ? { $_.href.ToLower().EndsWith('.iso') } | % {
    Write-Output "$($rootURL)$($_.href)"
  } | Select -First 1
  if ($url64bit -eq $null) { throw "Unable to determing the latest VMWare Tools package to download"}

  Write-Host "Downloading $url64bit"
  (New-Object System.Net.WebClient).DownloadFile($url64bit, $VMwareToolsISOPath) | Out-Null
}
#   Grab Server 2016 ISO
$Server2016ISO = "$sourcesDir\14300.1000.160324-1723.RS1_RELEASE_SVC_SERVER_OEMRET_X64FRE_EN-US.ISO"
if (-not (Test-Path -Path $Server2016ISO)) {
  Write-Host "Downloading Server 2016 TP5 ISO..."  
  $url64bit = 'http://int-resources.ops.puppetlabs.net/ISO/Windows/2016TP5Pre-Build-14300.1000.160324-1723.RS1/14300.1000.160324-1723.RS1_RELEASE_SVC_SERVER_OEMRET_X64FRE_EN-US.ISO'
  (New-Object System.Net.WebClient).DownloadFile($url64bit, $Server2016ISO) | Out-Null
}
#   Grab Cloudbase Offline
$CloudBaseOfflineInitZip = "$sourcesDir\CloudBase.zip"
if (-not (Test-Path -Path $CloudBaseOfflineInitZip)) {
  Write-Host "Downloading CloudBase Init Offline Install for Nano ..."  
  $url64bit = 'https://github.com/cloudbase/cloudbase-init-offline-install/archive/nano-server-support.zip'
  (New-Object System.Net.WebClient).DownloadFile($url64bit, $CloudBaseOfflineInitZip) | Out-Null
}
#   Grab the Win-OpenSSH 
$OpenSSHZip = "$sourcesDir\OpenSSH.zip"
if (-not (Test-Path -Path $OpenSSHZip)) {
  Write-Host "Downloading Win-OpenSSH..."  
  $url64bit = 'https://github.com/PowerShell/Win32-OpenSSH/releases/download/5_30_2016/OpenSSH-Win64.zip'
  (New-Object System.Net.WebClient).DownloadFile($url64bit, $OpenSSHZip) | Out-Null
}

# Extract the VMWare Tools ISO files...
Write-Host "Mounting VMWare Tools ISO..."
$isoMountDrive = (Mount-DiskImage $VMwareToolsISOPath -PassThru | Get-Volume).DriveLetter
try {
  $msiDir = "$tmpDir\msi"
  Write-Host "Extracting VMWare Tools..."
  
  $args = @('/a',"`"$($msiDir)`"",'/s','/v',"`"/qn REBOOT=ReallySuppress TARGETDIR=$msiDir`"",'/l',"$($tmpDir)\vmware_extract.log")
  Write-Host "Running: $($isoMountDrive):\setup64.exe $args"  
  Start-Process -File "$($isoMountDrive):\setup64.exe" -Argument $args -Wait -NoNewWindow | Out-Null

  $VmwareDriversPath = "$($msiDir)\Program Files\VMware\VMware Tools\VMware\Drivers"
}
finally {
  Write-Host "Dimounting VMWare Tools ISO..."
  Dismount-DiskImage $VMwareToolsISOPath
}

# Extract the Open-SSH package
Write-Host "Extracting Win-OpenSSH..."  
$tempOpenSSH = "$tmpDir\openssh"
[System.IO.Compression.ZipFile]::ExtractToDirectory($OpenSSHZip, $tempOpenSSH)

# Extract the Cloudbase Init package
Write-Host "Extracting Cloud Base for Nano..."  
$tempCloudBase = "$tmpDir\cloudbase"
[System.IO.Compression.ZipFile]::ExtractToDirectory($CloudBaseOfflineInitZip, $tempCloudBase)

# Create the extra files layout...
Write-Host "Creating Extra Files layout..."  
$ExtraFilesPaths = @{
  "$tempOpenSSH\OpenSSH-Win64" = "OpenSSH-Win64"
  "$sourcesDir\setuser\*" = "OpenSSH-Win64\"
  "$thisDir\Install-OpenSSH.PS1" = "Install-OpenSSH.ps1"
}
#  "$thisDir\SetupComplete.CMD" = "Windows\Setup\Scripts\"
New-Item -Path $tempExtraFiles -ItemType Directory | Out-Null
$ExtraFilesPaths.GetEnumerator() | % {
  $item = $_
  Write-Host "Adding files from $($item.Key) ..."
  $DestPath = "${tempExtraFiles}\$($item.Value)"
  # If it ends with '\' then the directory must exist prior to file copy
  if ($DestPath.EndsWith('\')) {
    if (-not (Test-Path -Path $DestPath)) {
      New-Item -Path $DestPath -Type Directory | Out-Null
    }
  }
  Copy-Item -Recurse -Path "$($item.Key)" -Destination $DestPath -Confirm:$false -Force | Out-Null
}

# Read in SetupComplete.CMD
$SetupComplete = ''
if (Test-Path -Path "$($thisDir)\SetupComplete.CMD") {
  $SetupComplete = Get-Content "$($thisDir)\SetupComplete.CMD"
}

# Time to build Nano
Write-Host "Time to build Nano...."
$IsoPath = $Server2016ISO
$MaxSize = 1.5GB
$DiskLayout = "BIOS"
$PackageList = @()
$ServerEdition = 'Standard'
$NanoServerDir = "$($thisDir)\NanoServer"
$featuresToEnable = @('File-Services')

if(Test-Path $TargetPath)
{
  throw "The target path ""`$TargetPath"" already exists, please remove it before running this script"
}
# Note: currently VHDX creates a GPT EFI image for Gen2, while VHD targets a MBR BIOS Gen1.
if($DiskLayout -eq "BIOS") # "BIOS", "UEFI"
{
  $vhdPathFormat = "vhd"
}
else
{
  $vhdPathFormat = "vhdx"
}

$diskFormat = [System.IO.Path]::GetExtension($TargetPath).substring(1).ToLower()
if ($diskFormat -eq $vhdPathFormat)
{
  $vhdPath = $TargetPath
}
else
{
  $vhdPath = "${TargetPath}.${vhdPathFormat}"
}

Write-Host "Creating base nano disk image at $($vhdPath)..."
$isoMountDrive = (Mount-DiskImage $IsoPath -PassThru | Get-Volume).DriveLetter
$isoNanoServerPath = "${isoMountDrive}:\NanoServer"
try
{
  Import-Module "${isoNanoServerPath}\NanoServerImageGenerator\NanoServerImageGenerator.psm1"
  New-NanoServerImage -MediaPath "${isoMountDrive}:\" -BasePath $NanoServerDir `
  -MaxSize $MaxSize -AdministratorPassword $AdministratorPassword -TargetPath $vhdPath `
  -DeploymentType 'Guest' -OEMDrivers:$false `
  -Compute:$false -Storage:$true -Clustering:$false -Containers:$false  `
  -Packages $PackageList -Edition $ServerEdition `
  -EnableRemoteManagementPort:$true -CopyFiles (Get-ChildItem -Path $tempExtraFiles | % { Write-Output $_.Fullname }) `
  -DriversPath $VmwareDriversPath -SetupCompleteCommands $SetupComplete
}
finally
{
  Dismount-DiskImage $IsoPath
}

Write-Host "Beginning to customise the nano image..."
$dismPath = Join-Path $NanoServerDir "Tools\dism.exe"
$mountDir = Join-Path $NanoServerDir "MountDir"

if(!(Test-Path $mountDir))
{
  mkdir $mountDir
}

Write-Host "Mounting the nano image..."
& $dismPath /Mount-Image /ImageFile:$vhdPath /Index:1 /MountDir:$mountDir
if($lastexitcode) { throw "dism /Mount-Image failed"}

try
{
  foreach($featureName in $featuresToEnable)
  {
    Write-Host "Enabling feature $($featureName)..."
    & $dismPath /Enable-Feature /image:$mountDir /FeatureName:$featureName
    if($lastexitcode) { throw "dism /Enable-Feature failed for feature: $featureName"}
  }

#read-host -Prompt "press enter"

}
finally
{
  Write-Host "Dismounting the image..."
  & $dismPath /Unmount-Image /MountDir:$mountDir /Commit
  if($lastexitcode) { throw "dism /Unmount-Image failed"}
}

Write-Host "Converting to VMDK..."
if(Test-Path -PathType Leaf $TargetPath)
{
  Write-Host "Removing previous disk at $TargetPath"
  del $TargetPath
}

Write-Host "Converting VHD to VMDK..."
& "$tempCloudBase\cloudbase-init-offline-install-nano-server-support\Bin\qemu-img.exe" convert -O "vmdk" $vhdPath $targetPath
if($lastexitcode) { throw "qemu-img.exe convert failed" }

Copy-Item -Path "C:\dev\transfer\nano.vmdk" -Destination "Z:\build-box-transfer\nano.vmdk" -Confirm:$false -Force | Out-Null