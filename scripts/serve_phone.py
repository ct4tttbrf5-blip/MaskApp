#!/usr/bin/env python3
"""Serve the phone-friendly web preview on the LAN.

No USB cable, no Apple ID, no signing, no cloud publishing. The iPhone and this
PC only need to be on the same Wi-Fi network.
"""
from __future__ import annotations

import functools
import http.server
import os
import socket
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "preview"
PORT = int(os.environ.get("MASKAPP_WEB_PORT", "8000"))


def lan_ip() -> str:
    """Return the address of the NIC that would reach the internet."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("223.5.5.5", 80))  # UDP connect sends nothing
        return s.getsockname()[0]
    except OSError:
        return socket.gethostbyname(socket.gethostname())
    finally:
        s.close()


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        # Keep the console readable; only surface real failures.
        if len(args) >= 2 and str(args[1]).startswith(("4", "5")):
            super().log_message(fmt, *args)

    def end_headers(self) -> None:
        # Never let an old cached copy survive an edit.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main() -> None:
    if not (ROOT / "index.html").is_file():
        raise SystemExit(f"找不到页面文件：{ROOT / 'index.html'}")
    ip = lan_ip()
    url = f"http://{ip}:{PORT}"
    handler = functools.partial(Handler, directory=str(ROOT))

    print("=" * 62)
    print("  电子面膜 3.0 · 手机网页版（不需要数据线）")
    print("=" * 62)
    print(f"  手机 Safari 打开：  {url}")
    print(f"  本机预览：          http://127.0.0.1:{PORT}")
    print()
    print("  1) 手机和电脑连同一个 WiFi")
    print("  2) Safari 打开上面的地址 → 分享 → 添加到主屏幕")
    print("  3) 桌面会多出图标，点开即全屏运行，无地址栏")
    print()
    print("  首次运行若弹出 Windows 防火墙提示，请勾选「专用网络」")
    print("  并允许访问；手机打不开多半是防火墙拦了 Python。")
    print("  电脑要一直开着、服务不能关。按 Ctrl+C 停止。")
    print("=" * 62, flush=True)

    try:
        httpd = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), handler)
    except OSError as e:
        raise SystemExit(
            f"端口 {PORT} 启动失败（{e}）。可换端口重试：\n"
            f"    MASKAPP_WEB_PORT=8080 python scripts/serve_phone.py"
        ) from e
    with httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n服务已停止。")


if __name__ == "__main__":
    main()
