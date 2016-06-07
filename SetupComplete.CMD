@ECHO OFF

REM Install SSHD Server
DATE /T > C:\Setup.log
TIME /T >> C:\Setup.log

powershell "& { . C:\Install-OpenSSH.PS1}" >> C:\Setup.Log

shutdown /r /t 0 /f