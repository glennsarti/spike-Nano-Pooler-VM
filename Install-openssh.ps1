# Modified from the Chocolatey Installation Script from DarwinJS
# FROM https://chocolatey.org/packages/win32-openssh/2016.05.30

# TODO Need to add the RSA Acceptance Certificate

$ErrorActionPreference = 'Stop'; # stop on all errors
 
$SSHLsaVersionChanged = $true
If (Test-Path "$env:windir\system32\ssh-lsa.dll") {
  #Using file size because open ssh files are not currently versioned.  Submitted problem report asking for versioning to be done
  If (((get-item $env:windir\system32\ssh-lsa.dll).length) -eq ((get-item $TargetFolder\ssh-lsa.dll).length))
  {$SSHLsaVersionChanged = $false}
}
 
$SSHServerFeature = $true
$KeyBasedAuthenticationFeature = $false
$TargetFolder = 'C:\OpenSSH-Win64'

$toolsDir = "$TargetFolder\tools"

If ($SSHServerFeature)
{
  Write-Warning "You have specified SSHServerFeature - this machine is being configured as an SSH Server including opening port 22."
  If ($KeyBasedAuthenticationFeature)
  {
    Write-Warning "You have specified KeyBasedAuthenticationFeature - a new lsa provider will be installed."
    $sys32dir = "$env:windir\system32"
 
    If ($SSHLsaVersionChanged)
    {
      Copy-Item "$TargetFolder\ssh-lsa.dll" "$sys32dir\ssh-lsa.dll" -Force
    }
 
    #Don't destroy other values
    $key = get-item 'Registry::HKLM\System\CurrentControlSet\Control\Lsa'
    $values = $key.GetValue("Authentication Packages")
    $values += 'msv1_0\0ssh-lsa.dll'
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\" "Authentication Packages" $values
  }
 
  If((Test-Path "$TargetFolder\sshd_config") -AND ([bool]((gc "$TargetFolder\sshd_config") -ilike "*#LogLevel INFO*")))
  {
    Write-Warning "Explicitly disabling sshd logging as it currently logs about .5 GB / hour"
    (Get-Content "$TargetFolder\sshd_config") -replace '#LogLevel INFO', 'LogLevel QUIET' | Set-Content "$TargetFolder\sshd_config"
  }
 
  If (!(Test-Path "$TargetFolder\KeysGenerated.flg")) {
    Write-Output "Generating sshd keys in `"$TargetFolder`""
    start-process "$TargetFolder\ssh-keygen.exe" -ArgumentList '-A' -WorkingDirectory "$TargetFolder" -nonewwindow -wait
    New-Item "$TargetFolder\KeysGenerated.flg" -type File | out-null
  }
  Else
  {
    Write-Warning "Found existing server ssh keys in $TargetFolder, you must delete them manually to generate new ones."
  }
 
  netsh advfirewall firewall add rule name='SSHD Port win32-openssh' dir=in action=allow protocol=TCP localport=22
  New-Service -Name ssh-agent -BinaryPathName "$TargetFolder\ssh-agent.exe" -Description "SSH Agent" -StartupType Automatic | Out-Null
  cmd.exe /c 'sc.exe sdset ssh-agent D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)(A;;RP;;;AU)'
 
  Start-Service ssh-agent
 
  Start-Sleep -seconds 3
 
  $keylist = "ssh_host_dsa_key", "ssh_host_rsa_key", "ssh_host_ecdsa_key", "ssh_host_ed25519_key"
  $fullpathkeylist = "'$TargetFolder\ssh_host_dsa_key'", "'$TargetFolder\ssh_host_rsa_key'", "'$TargetFolder\ssh_host_ecdsa_key'", "'$TargetFolder\ssh_host_ed25519_key'"
 
  schtasks.exe /create /RU "NT AUTHORITY\SYSTEM" /RL HIGHEST /SC ONSTART /TN "ssh-add" /TR "'$TargetFolder\ssh-add.exe'  $fullpathkeylist" /F 
  schtasks.exe /Run /I /TN "ssh-add" 
  schtasks.exe /Delete /TN "ssh-add" /F

  New-Service -Name sshd -BinaryPathName "$TargetFolder\sshd.exe" -Description "SSH Deamon" -StartupType Automatic -DependsOn ssh-agent | Out-Null
  sc.exe config sshd obj= "NT SERVICE\SSHD"
 
  & "$TargetFolder\SetUserAccountRights.exe" -g "NT SERVICE\SSHD" -v SeServiceLogonRight
  & "$TargetFolder\SetUserAccountRights.exe" -g "NT SERVICE\SSHD" -v SeAssignPrimaryTokenPrivilege

  If (!$SSHLsaVersionChanged)
  {
    Write-Output "Starting sshd Service"
    Start-Service sshd
  }
  Else
  {
    Write-Warning "You must reboot so that key based authentication can be fully installed for the SSHD Service."
  }
}
 
Write-Warning "You must start a new prompt, or re-read the environment for the tools to be available in your command line environment."
