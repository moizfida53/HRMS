@echo off
rem HRMS - set the database connection on this server (double-click). See Set-DatabaseConnection.ps1.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-DatabaseConnection.ps1"
echo.
pause
