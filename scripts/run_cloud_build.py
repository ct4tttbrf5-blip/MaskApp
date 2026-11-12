#!/usr/bin/env python3
"""Push MaskApp to GitHub, wait for the macOS CI build, download the unsigned IPA.

Usage:
    python scripts/run_cloud_build.py <owner>/<repo>

Token (never printed, never written into the repo):
    file  D:/BaiduSyncdisk/dnjswork/APP/.maskapp-token   (single line), or
    env   MASKAPP_GH_TOKEN

Required permissions: classic PAT with `repo` + `workflow`, or a fine-grained
token with Contents (RW), Workflows (RW), Actions (R), Metadata (R).
The repository should be Public - public repos get free macOS runners.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKEN_FILE = ROOT.parent / ".maskapp-token"
API = "https://api.github.com"
UA = "maskapp-cloud-build"


def load_token() -> str:
    token = os.environ.get("MASKAPP_GH_TOKEN", "").strip()
    if not token and TOKEN_FILE.exists():
        lines = TOKEN_FILE.read_text(encoding="utf-8").strip().splitlines()
        if lines:
            token = lines[0].strip()
    if not token:
        sys.exit(f"No token. Put it in {TOKEN_FILE} (one line) or set MASKAPP_GH_TOKEN.")
    return token


def api(path: str, token: str, method: str = "GET", payload=None):
    url = path if path.startswith("http") else API + path
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", UA)
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            body = response.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:600]
        sys.exit(f"GitHub API {method} {url} -> {error.code}: {detail}")


def download_redirect(url: str, token: str) -> bytes:
    """GitHub artifact / log endpoints answer with a 302 to a signed URL.
    Do not forward the Authorization header to that third-party host."""

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(NoRedirect)
    req = urllib.request.Request(url)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("User-Agent", UA)
    try:
        with opener.open(req, timeout=60) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        if error.code in (301, 302, 303, 307, 308):
            location = error.headers.get("Location")
            if location:
                with urllib.request.urlopen(location, timeout=180) as response:
                    return response.read()
        sys.exit(f"Download failed: {error.code} for {url}")


def git(*args, token: str = "", check: bool = True):
    result = subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True
    )
    if check and result.returncode:
        safe = (result.stdout + result.stderr)
        if token:
            safe = safe.replace(token, "***")
        sys.exit("git " + " ".join(args) + " failed:\n" + safe[:2000])
    return result.stdout.strip()


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("Usage: python scripts/run_cloud_build.py <owner>/<repo>")
    repo = (
        sys.argv[1].strip()
        .replace("https://github.com/", "")
        .removesuffix(".git")
        .strip("/")
    )
    if "/" not in repo:
        sys.exit("Repository must look like owner/repo")

    token = load_token()

    # 1. Verify credentials and repository
    user = api("/user", token)
    print(f"[1/5] Authenticated as {user['login']}")
    info = api(f"/repos/{repo}", token)
    print(f"      Repository {info['full_name']} (private={info['private']})")
    if info["private"]:
        print("      Note: private repos bill macOS minutes at 10x the free quota.")

    # 2. Push. The token goes through a temporary http.extraheader, so it
    #    never lands in .git/config, the remote URL, or the command output.
    head = git("rev-parse", "HEAD", token=token)
    git("remote", "remove", "origin", token=token, check=False)
    git("remote", "add", "origin", f"https://github.com/{repo}.git", token=token)
    credential = base64.b64encode(f"x-access-token:{token}".encode()).decode()
    env = dict(os.environ)
    env["GIT_TERMINAL_PROMPT"] = "0"
    push = subprocess.run(
        [
            "git",
            "-c", "credential.helper=",
            "-c", f"http.extraheader=AUTHORIZATION: basic {credential}",
            "push", "-u", "origin", "main",
        ],
        cwd=ROOT, capture_output=True, text=True, env=env,
    )
    if push.returncode:
        safe = (push.stdout + push.stderr).replace(token, "***").replace(credential, "***")
        sys.exit("[2/5] Push failed:\n" + safe[:2000])
    print(f"[2/5] Pushed commit {head[:7]} to main")

    # 3. Find the CI run (push should trigger it; dispatch as a fallback)
    start = time.time()
    dispatched = False
    run = None
    while time.time() - start < 1200:
        runs = api(f"/repos/{repo}/actions/runs?per_page=10", token)["workflow_runs"]
        matches = [r for r in runs if r["head_sha"] == head]
        if matches:
            run = matches[0]
            if run["status"] == "completed":
                break
            print(f"[3/5] Build {run['status']} ... {int(time.time() - start)}s", flush=True)
        elif not dispatched and time.time() - start > 30:
            api(
                f"/repos/{repo}/actions/workflows/build-ipa.yml/dispatches",
                token, "POST", {"ref": "main"},
            )
            dispatched = True
            print("[3/5] No auto run detected, dispatched manually", flush=True)
        time.sleep(15)

    if run is None:
        sys.exit("[3/5] No CI run appeared within 20 minutes. Check the Actions tab.")
    print(f"[3/5] Run #{run['run_number']} finished: {run['conclusion']} "
          f"({run['html_url']})")

    # 4. On failure, pull the job log so the error can be fixed
    if run["conclusion"] != "success":
        jobs = api(f"/repos/{repo}/actions/runs/{run['id']}/jobs", token)["jobs"]
        for job in jobs:
            if job["conclusion"] == "failure":
                print(f"      Failing step log ({job['name']}):")
                try:
                    raw = download_redirect(
                        f"{API}/repos/{repo}/actions/jobs/{job['id']}/logs", token
                    )
                    lines = raw.decode("utf-8", "replace").splitlines()
                    for line in lines[-60:]:
                        print("      " + line[:200])
                except SystemExit as error:
                    print("      " + str(error))
                break
        sys.exit("[4/5] Build failed. Log above; fix and re-run this script.")

    # 5. Download the artifact and extract the IPA
    artifacts = api(
        f"/repos/{repo}/actions/runs/{run['id']}/artifacts", token
    )["artifacts"]
    if not artifacts:
        sys.exit("[5/5] Build succeeded but no artifact was uploaded.")
    artifact = artifacts[0]
    print(f"[5/5] Downloading artifact {artifact['name']} "
          f"({artifact['size_in_bytes'] // 1024} KB)")
    raw = download_redirect(artifact["archive_download_url"], token)

    out_dir = ROOT / "build-output"
    out_dir.mkdir(exist_ok=True)
    archive = out_dir / "artifact.zip"
    archive.write_bytes(raw)
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(out_dir)
    ipa = next(out_dir.rglob("*.ipa"), None)
    if ipa is None:
        sys.exit("[5/5] Artifact downloaded but contains no .ipa file.")
    print("\nDONE - unsigned IPA ready:")
    print(f"  {ipa}  ({ipa.stat().st_size // 1024} KB)")
    print("\nNext: sign and install with AltStore (README.md section 3).")


if __name__ == "__main__":
    main()
