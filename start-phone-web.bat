@echo off
chcp 65001 >nul
title MaskApp - Phone Web Preview (no USB)
cd /d "%~dp0"
echo.
echo   Starting local web server for your iPhone...
echo   Keep this window open while using the app on your phone.
echo.
python scripts\serve_phone.py
if errorlevel 1 (
  echo.
  echo   [FAILED] Python not found? Install Python and make sure it is in PATH.
)
echo.
pause
