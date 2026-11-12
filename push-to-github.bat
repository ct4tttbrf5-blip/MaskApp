@echo off
chcp 65001 >nul
title MaskApp - Push to GitHub
cd /d "%~dp0"

echo.
echo   ==========================================================
echo     MaskApp - 推送到 GitHub 并自动开始云端编译
echo   ==========================================================
echo.
echo   准备：在 GitHub 网页新建一个空仓库（选 Public），
echo         不要勾选 README / .gitignore / license。
echo   示例： https://github.com/yourname/MaskApp.git
echo.
set "REPO="
set /p "REPO=粘贴仓库地址后回车: "
if not defined REPO (
  echo   未输入地址，已取消。
  pause
  exit /b 1
)

echo.
echo   [1/2] 配置远端并推送...
git remote remove origin >nul 2>&1
git remote add origin "%REPO%"
git push -u origin main
if errorlevel 1 (
  echo.
  echo   [推送失败] 常见原因：
  echo     - 仓库地址写错，或仓库尚未创建
  echo     - 未登录 GitHub：若弹出登录窗口，完成授权后重新运行本脚本
  echo     - 建仓库时勾选了 README，导致远端已有提交
  echo.
  pause
  exit /b 1
)

echo.
echo   [2/2] 推送成功，云端编译已自动开始，约 5-10 分钟。
set "ACTIONS=%REPO:.git=/actions%"
echo   正在打开 Actions 页面：%ACTIONS%
start "" "%ACTIONS%"
echo.
echo   编译结束后：点开最新一次运行，在底部 Artifacts
echo   下载 MaskApp-unsigned-ipa，解压得到 MaskApp-unsigned.ipa。
echo   安装步骤见 README.md 第三节。
echo.
pause
