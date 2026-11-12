#!/usr/bin/env python3
"""Authorise without opening GitHub on this PC (device-code flow).

Use this when github.com is too slow / times out in the browser here.
You only need a device that CAN reach github.com - a phone on mobile data is
usually enough.

It uses the public OAuth client id of GitHub's own CLI (GitHub CLI), so the
consent page will show "GitHub CLI" as the application name. Nothing is sent
to any third party: the code is exchanged directly with github.com, and the
resulting token is stored only in the local file below.

    Token file: D:/BaiduSyncdisk/dnjswork/APP/.maskapp-token

Revoke when done: https://github.com/settings/applications
"""

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKEN_FILE = ROOT.parent / ".maskapp-token"

CLIENT_ID = "178c6fc778ccc68e1d6a"  # public client id of GitHub CLI
DEVICE_URL = "https://github.com/login/device/code"
TOKEN_URL = "https://github.com/login/oauth/access_token"
API = "https://api.github.com"
SCOPES = "repo workflow"


def post(url: str, payload: dict, retries: int = 4) -> dict:
    data = json.dumps(payload).encode()
    for attempt in range(retries):
        req = urllib.request.Request(url, data=data, method="POST")
        req.add_header("Accept", "application/json")
        req.add_header("Content-Type", "application/json")
        req.add_header("User-Agent", "maskapp-cloud-build")
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                return json.loads(response.read())
        except urllib.error.HTTPError as error:
            # Device-flow pending is reported by the polling endpoint as 200,
            # so an HTTP error here is a real failure.
            detail = error.read().decode("utf-8", "replace")[:400]
            if error.code >= 500 and attempt < retries - 1:
                time.sleep(3 * (attempt + 1))
                continue
            sys.exit(f"github.com returned {error.code}: {detail}")
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            if attempt < retries - 1:
                print(f"  Network slow ({error}), retrying ...", flush=True)
                time.sleep(3 * (attempt + 1))
                continue
            sys.exit(f"Cannot reach github.com: {error}\n"
                     f"Try a mobile hotspot, or generate a classic PAT instead.")
    sys.exit("Giving up: github.com did not respond.")


def verify(token: str) -> None:
    """Show who we are logged in as, and catch missing scopes early."""
    req = urllib.request.Request(API + "/user")
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "maskapp-cloud-build")
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            login = json.loads(response.read())["login"]
            scopes = response.headers.get("X-OAuth-Scopes", "")
    except (urllib.error.URLError, OSError, KeyError) as error:
        print(f"  (Could not verify the token: {error})")
        return
    print(f"  已登录为 {login}；权限：{scopes or '(响应未返回)'}")
    if scopes and "repo" not in scopes:
        print("  警告：权限里没有 repo，后续建仓库/推送可能失败，请重新授权。")


def main() -> None:
    print("GitHub 设备码授权（电脑上不需要打开 GitHub 网页）")
    print("=" * 56)
    result = post(DEVICE_URL, {"client_id": CLIENT_ID, "scope": SCOPES})
    code = result["user_code"]
    device_code = result["device_code"]
    uri = result.get("verification_uri", "https://github.com/login/device")
    interval = max(int(result.get("interval", 5)), 5)
    expires = int(result.get("expires_in", 900))

    print("\n  请用手机浏览器打开（建议用流量，不要用同一个 WiFi）：\n")
    print(f"      {uri}\n")
    print(f"  输入验证码：  {code}\n")
    print("  登录你的 GitHub 账号 -> 点 Continue / Authorize。")
    print("  授权页会显示应用名 GitHub CLI，这是 GitHub 官方命令行工具，正常。")
    print(f"\n  验证码 {expires // 60} 分钟内有效。授权后这里会自动继续 ...\n")

    deadline = time.time() + expires
    while time.time() < deadline:
        time.sleep(interval)
        reply = post(
            TOKEN_URL,
            {
                "client_id": CLIENT_ID,
                "device_code": device_code,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            },
        )
        error = reply.get("error")
        if not error and reply.get("access_token"):
            token = reply["access_token"]
            TOKEN_FILE.write_text(token + "\n", encoding="utf-8")
            try:
                TOKEN_FILE.chmod(0o600)
            except OSError:
                pass
            print(f"  授权成功，已保存（不显示内容）：\n      {TOKEN_FILE}\n")
            verify(token)
            print("\n  现在执行： python scripts/run_cloud_build.py")
            print("  跑完后请到 https://github.com/settings/applications 撤销授权。")
            return
        if error == "authorization_pending":
            print("  等待你在手机上确认 ...", flush=True)
            continue
        if error == "slow_down":
            interval += 5
            continue
        if error == "expired_token":
            sys.exit("  验证码已过期，请重新运行本脚本。")
        if error == "access_denied":
            sys.exit("  你取消了授权。需要时重新运行本脚本。")
        sys.exit(f"  授权失败：{error} - {reply.get('error_description', '')}")

    sys.exit("  验证码已过期，请重新运行本脚本。")


if __name__ == "__main__":
    main()
