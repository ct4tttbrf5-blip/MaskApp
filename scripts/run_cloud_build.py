#!/usr/bin/env python3
"""Create the repo, upload the source, run the macOS CI build, fetch the IPA.

Usage:
    python scripts/run_cloud_build.py                 # auto: <your-login>/MaskApp
    python scripts/run_cloud_build.py MaskApp        # <your-login>/MaskApp
    python scripts/run_cloud_build.py owner/repo     # explicit repository

IMPORTANT (why this does not use `git push`):
    Everything goes through api.github.com ONLY. On some CN links the
    github.com website / git endpoint is slow or drops connections while
    api.github.com stays fast and stable. The repository is created, files are
    uploaded with the Git Data API, the CI run is watched and the artifact is
    downloaded - no browser page, no git smart-HTTP, no `github.com` host.

Token (never printed, never written into the repo):
    file  D:/BaiduSyncdisk/dnjswork/APP/.maskapp-token   (single line), or
    env   MASKAPP_GH_TOKEN

    Classic PAT with `repo` + `workflow` is the reliable option. If the GitHub
    website will not open on this PC, generate the PAT in a PHONE browser (use
    mobile data) and copy it into that file. scripts/github_device_login.py is
    an alternative, but its endpoint lives on the less reliable github.com host.

Revoke the token when done: https://github.com/settings/tokens
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
DEFAULT_REPO = "MaskApp"


def load_token() -> str:
    token = os.environ.get("MASKAPP_GH_TOKEN", "").strip()
    if not token and TOKEN_FILE.exists():
        # utf-8-sig also tolerates a BOM written by Windows Notepad / PowerShell 5.1
        lines = TOKEN_FILE.read_text(encoding="utf-8-sig").strip().splitlines()
        if lines:
            token = lines[0].strip()
    if not token:
        sys.exit(
            f"No token found.\n"
            f"  Put it on one line in: {TOKEN_FILE}\n"
            f"  Easiest when the website is down: create the PAT in a phone\n"
            f"  browser (mobile data), then copy it into that file.\n"
            f"  Alternative: python scripts/github_device_login.py"
        )
    return token


def api(path: str, token: str, method: str = "GET", payload=None,
        *, missing_ok: bool = False, missing_codes=(404,),
        retries: int = 4, timeout: int = 60):
    """Call GitHub REST API with retries for slow / flaky links."""
    url = path if path.startswith("http") else API + path
    data = json.dumps(payload).encode() if payload is not None else None
    last_error = ""
    for attempt in range(retries):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + token)
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        req.add_header("User-Agent", UA)
        if data:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as response:
                body = response.read()
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as error:
            if missing_ok and error.code in missing_codes:
                return None
            detail = error.read().decode("utf-8", "replace")[:600]
            if error.code >= 500 and attempt < retries - 1:
                print(f"      API {error.code}, retry {attempt + 1}/{retries - 1} ...",
                      flush=True)
                time.sleep(3 * (attempt + 1))
                continue
            if error.code == 403 and url.endswith("/user/repos"):
                sys.exit(
                    "This token cannot create repositories. Use a classic PAT with "
                    "`repo` + `workflow`, or create the empty repo on GitHub once "
                    "and re-run."
                )
            sys.exit(f"GitHub API {method} {url} -> {error.code}: {detail}")
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            last_error = str(error)
            if attempt < retries - 1:
                print(f"      Network slow ({last_error}), "
                      f"retry {attempt + 1}/{retries - 1} ...", flush=True)
                time.sleep(3 * (attempt + 1))
                continue
            sys.exit(
                f"Network error calling {url}: {last_error}\n"
                f"GitHub can be slow on this link. Try again, or switch to a "
                f"mobile hotspot."
            )
    sys.exit(f"Giving up on {url}: {last_error}")


def download_redirect(url: str, token: str) -> bytes:
    """Artifact / log endpoints answer with a 302 to a signed URL.
    Do not forward the Authorization header to that third-party host."""

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(NoRedirect)
    req = urllib.request.Request(url)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("User-Agent", UA)
    try:
        with opener.open(req, timeout=90) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        if error.code in (301, 302, 303, 307, 308):
            location = error.headers.get("Location")
            if location:
                with urllib.request.urlopen(location, timeout=240) as response:
                    return response.read()
        sys.exit(f"Download failed: {error.code} for {url}")


def collect_files():
    """Tracked + new (non-ignored) files, with git's own path separator."""
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT, capture_output=True, text=True,
    )
    if result.returncode:
        sys.exit("Cannot list project files with git:\n" + result.stderr[:1000])
    paths = []
    for line in result.stdout.splitlines():
        rel = line.strip()
        if not rel or rel.startswith(".git/"):
            continue
        path = ROOT / rel
        if path.is_file():
            paths.append(rel)
    if not paths:
        sys.exit("No source files found - is this the MaskApp directory?")
    return sorted(paths)


def push_via_api(repo: str, token: str, files) -> str:
    """Upload the working tree through the Git Data API; return the commit sha."""
    # A truly empty repo answers 409 "Git Repository is empty" on EVERY Git
    # Data API endpoint (refs, blobs, trees). Seed one initial commit through
    # the Contents API first - that endpoint does work on an empty repo.
    info = api(f"/repos/{repo}", token)
    if info.get("size", 0) == 0:
        print("      empty repo - seeding an initial commit ...", flush=True)
        api(f"/repos/{repo}/contents/.gitkeep", token, "PUT", {
            "message": "Initialize repository",
            "content": base64.b64encode(b"\n").decode(),
        })
        time.sleep(1)

    ref = api(f"/repos/{repo}/git/ref/heads/main", token,
              missing_ok=True, missing_codes=(404, 409))
    base_sha = ref["object"]["sha"] if ref else None
    base_tree = None
    if base_sha:
        base_tree = api(f"/repos/{repo}/git/commits/{base_sha}", token)["tree"]["sha"]

    entries = []
    for index, rel in enumerate(files, 1):
        content = (ROOT / rel).read_bytes()
        blob = api(f"/repos/{repo}/git/blobs", token, "POST", {
            "content": base64.b64encode(content).decode(),
            "encoding": "base64",
        })
        entries.append({"path": rel, "mode": "100644", "type": "blob",
                        "sha": blob["sha"]})
        if index % 6 == 0 or index == len(files):
            print(f"      uploaded {index}/{len(files)} files ...", flush=True)

    tree = api(f"/repos/{repo}/git/trees", token, "POST", {"tree": entries})
    if tree["sha"] == base_tree:
        print("      content unchanged - reusing existing commit", flush=True)
        return base_sha

    payload = {
        "message": "Build MaskApp (uploaded via GitHub API)",
        "tree": tree["sha"],
    }
    if base_sha:
        payload["parents"] = [base_sha]
    commit = api(f"/repos/{repo}/git/commits", token, "POST", payload)
    sha = commit["sha"]

    if ref:
        api(f"/repos/{repo}/git/refs/heads/main", token, "PATCH", {"sha": sha})
    else:
        api(f"/repos/{repo}/git/refs", token, "POST",
            {"ref": "refs/heads/main", "sha": sha})
    return sha


def main() -> None:
    arg = (sys.argv[1].strip() if len(sys.argv) > 1 else "")
    arg = (arg.replace("https://github.com/", "")
              .removesuffix(".git").strip("/"))

    token = load_token()

    # 1. Authenticate, resolve the repo, create it if needed (no browser needed)
    user = api("/user", token)
    login = user["login"]
    print(f"[1/5] Authenticated as {login}")
    if not arg:
        repo = f"{login}/{DEFAULT_REPO}"
        print(f"      No repo given -> using {repo}")
    elif "/" not in arg:
        repo = f"{login}/{arg}"
    else:
        repo = arg

    info = api(f"/repos/{repo}", token, missing_ok=True)
    if info is None:
        name = repo.split("/", 1)[1]
        print(f"      {repo} not found -> creating PUBLIC repo via API ...", flush=True)
        info = api("/user/repos", token, "POST", {
            "name": name,
            "description": "Mask 3.0 iOS controller (SwiftUI + CoreBluetooth)",
            "private": False,
            # Seed an initial commit: GitHub's Git Data API returns 409 on a
            # completely empty repository. The full tree upload below replaces
            # this README anyway, so the final repo contains only our files.
            "auto_init": True,
            "has_issues": False,
            "has_projects": False,
            "has_wiki": False,
        })
        print(f"      Created: {info['html_url']}", flush=True)
        time.sleep(2)
    print(f"      Repository {info['full_name']} (private={info['private']})")
    if info["private"]:
        print("      Note: private repos bill macOS minutes at 10x the free quota.")

    # 2. Upload source via api.github.com (never touches github.com / git push)
    files = collect_files()
    print(f"[2/5] Uploading {len(files)} files via GitHub API ...", flush=True)
    head = push_via_api(repo, token, files)
    print(f"[2/5] Commit {head[:7]} is now on main")

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
            print(f"[3/5] Build {run['status']} ... {int(time.time() - start)}s",
                  flush=True)
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
    print("\nNote: main was updated through the API; your local git history does")
    print("      not need to be in sync for the build to work.")
    print("Next: sign and install with AltStore (README.md section 3).")


if __name__ == "__main__":
    main()
