@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo.
where python >nul 2>nul
if %errorlevel%==0 (
  python scripts/github_device_login.py
) else (
  py scripts/github_device_login.py
)
echo.
pause
