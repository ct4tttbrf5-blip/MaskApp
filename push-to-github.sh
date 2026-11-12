#!/usr/bin/env bash
# 在 Git Bash 里运行： bash push-to-github.sh
set -e
cd "$(dirname "$0")"

echo
echo "  =========================================================="
echo "   MaskApp - 推送到 GitHub 并自动开始云端编译"
echo "  =========================================================="
echo
echo "  准备：在 GitHub 网页新建一个空仓库（选 Public），"
echo "        不要勾选 README / .gitignore / license。"
echo "  示例： https://github.com/yourname/MaskApp.git"
echo
read -r -p "  粘贴仓库地址后回车: " REPO
if [ -z "$REPO" ]; then
  echo "  未输入地址，已取消。"
  exit 1
fi

echo
echo "  [1/2] 配置远端并推送..."
git remote remove origin >/dev/null 2>&1 || true
git remote add origin "$REPO"
if ! git push -u origin main; then
  echo
  echo "  [推送失败] 常见原因："
  echo "    - 仓库地址写错，或仓库尚未创建"
  echo "    - 未登录 GitHub：若弹出登录窗口，完成授权后重新运行本脚本"
  echo "    - 建仓库时勾选了 README，导致远端已有提交"
  exit 1
fi

echo
echo "  [2/2] 推送成功，云端编译已自动开始，约 5-10 分钟。"
ACTIONS="${REPO%.git}/actions"
echo "  Actions 页面：$ACTIONS"
if command -v explorer.exe >/dev/null 2>&1; then
  explorer.exe "$ACTIONS" >/dev/null 2>&1 || true
fi
echo
echo "  编译结束后：点开最新一次运行，在底部 Artifacts"
echo "  下载 MaskApp-unsigned-ipa，解压得到 MaskApp-unsigned.ipa。"
echo "  安装步骤见 README.md 第三节。"
echo
