@echo off
chcp 65001 >nul
title MaskApp - IPA download for iPhone (LAN)
cd /d "%~dp0"
echo.
echo   Serving the IPA download page to your iPhone...
echo   Keep this window open until the download finishes.
echo.
python scripts\serve_phone.py phone-install
if errorlevel 1 (
  echo.
  echo   [FAILED] Python not found? Install Python and make sure it is in PATH.
)
echo.
pause
