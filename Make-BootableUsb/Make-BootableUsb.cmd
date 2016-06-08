@echo off
pushd %~dp0
powershell -ExecutionPolicy bypass .\Make-BootableUsb.ps1 %~dp0Image
Pause
popd