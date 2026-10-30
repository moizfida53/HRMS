@echo off
title TMM POS Print Agent
cd /d "%~dp0"
:loop
node pos-print-agent.js
echo Agent stopped. Restarting in 5 seconds...
timeout /t 5 >nul
goto loop
