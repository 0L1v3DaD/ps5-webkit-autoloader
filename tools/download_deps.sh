#!/usr/bin/env bash
# Download the shared ps5-elfldr ELF and the ps5-unified-autoloader payload
# ELF from their GitHub releases, pinned to the third_party/ submodules.
#
#   third_party/ps5-elfldr             -> frontend/autoloader/shared/elfldr-ps5.elf
#   third_party/ps5-unified-autoloader -> frontend/autoloader/payloads/payload.elf
#
# The shared elfldr is used by the slopkit chain (9.00-12.00); umtx2
# (1.00-5.50) boots its own elfldr from the umtx2 submodule, like stock umtx2.
# The unified-autoloader payload is the "bundled" ELF embedded in the installer:
# after install, the homescreen app runs the exploit chain and autoloads it from
# the local AppCache.
#
# Neither is rebuilt here — both ship as prebuilt release assets (same approach
# as ps5-y2jb-autoloader's scripts/download_deps.sh), pinned to the submodule
# commits so builds are reproducible: bump the submodule to bump the payload.
#
# The elfldr tag is pinned explicitly (not via git describe) because ps5-elfldr
# tags multiple builds against one commit and describe picks an older tag; keep
# ELFLDR_TAG in sync when bumping third_party/ps5-elfldr.
#
# Idempotent: skips assets that already exist and match their cached sha256.
# The Makefile runs this automatically (payload-deps) before staging the
# frontend and building the PC host.
#
# Uses only python3 (a build dependency already) — no curl required, so it
# also runs inside the Docker SDK image.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Shared elfldr (same ELF across all exploit chains)
ELFLDR_SUBMODULE="$ROOT/third_party/ps5-elfldr"
ELFLDR_REPO="itsPLK/ps5-elfldr"
ELFLDR_TAG="v0.24-148b71c"
ELFLDR_DEST="$ROOT/frontend/autoloader/shared/elfldr-ps5.elf"

# Bundled autoload payload
PAYLOAD_SUBMODULE="$ROOT/third_party/ps5-unified-autoloader"
PAYLOAD_REPO="itsPLK/ps5-unified-autoloader"
DEFAULT_PAYLOAD_TAG="v0.1.4-955249d"
PAYLOAD_DEST="$ROOT/frontend/autoloader/payloads/payload.elf"

# Fetch the pinned release, verify the payload, and download it if needed.
# Exit codes: 0 = asset ready, 3 = already present and verified.
download_release() {
    local repo="$1" tag="$2" dest="$3"
    python3 - "$repo" "$tag" "$dest" <<'PY'
import gzip
import hashlib
import json
import os
import re
import sys
import time
import urllib.request

repo, tag, dest = sys.argv[1], sys.argv[2], sys.argv[3]
sidecar = dest + ".sha256"  # "<tag> <sha256>" cached after a successful verify

def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

# Offline fast path: asset + sidecar from a previous successful run.
if os.path.isfile(dest) and os.path.isfile(sidecar):
    with open(sidecar, "r", encoding="utf-8") as f:
        try:
            st_tag, st_hash = f.read().split()
        except ValueError:
            st_tag, st_hash = "", ""
    if st_tag == tag and sha256_of(dest).lower() == st_hash.lower():
        print(f"{os.path.basename(dest)} already present and verified ({tag}).")
        sys.exit(0)
    print(f"Existing asset {os.path.basename(dest)} does not match pinned release ({tag}) - re-checking...")

def fetch(url, attempts=5):
    """Fetch a URL, tolerating GitHub's flaky release CDN and rate limits."""
    last = None
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    for i in range(attempts):
        headers = {
            "User-Agent": "ps5-webkit-autoloader-build",
            "Accept-Encoding": "gzip",
        }
        # Only send Authorization to GitHub API, never to asset CDN redirects
        if token and url.startswith("https://api.github.com/"):
            headers["Authorization"] = f"Bearer {token}"
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = resp.read()
                if resp.headers.get("Content-Encoding", "").lower() == "gzip":
                    data = gzip.decompress(data)
                return data
        except Exception as exc:
            last = exc
            wait = 2 ** i
            if i < attempts - 1:
                print(f"  [retry {i + 1}/{attempts}] {exc} - retrying in {wait}s...", file=sys.stderr)
                time.sleep(wait)
    raise last

try:
    release_data = fetch(f"https://api.github.com/repos/{repo}/releases/tags/{tag}")
    release = json.loads(release_data.decode("utf-8", "replace"))
except Exception as exc:
    print(f"Error: could not fetch release metadata for {repo}@{tag} ({exc}).", file=sys.stderr)
    sys.exit(1)

asset = None
for a in release.get("assets", []):
    if a.get("name", "").endswith(".elf"):
        asset = a
        break
if asset is None:
    print(f"Error: release {tag} has no .elf asset.", file=sys.stderr)
    sys.exit(1)

digest = asset.get("digest", "")
if ":" in digest:
    digest = digest.split(":", 1)[-1].strip().lower()
else:
    digest = digest.strip().lower()

# Fallback: check if release contains a companion .sha256 asset
if not digest:
    for a in release.get("assets", []):
        aname = a.get("name", "")
        if aname == asset.get("name", "") + ".sha256" or aname.endswith(".sha256"):
            try:
                sha_content = fetch(a["browser_download_url"]).decode("utf-8", "replace")
                m = re.search(r"([a-fA-F0-9]{64})", sha_content)
                if m:
                    digest = m.group(1).lower()
                    break
            except Exception:
                pass

# Already downloaded and matching the pinned release? Just cache the digest.
if os.path.isfile(dest) and digest and sha256_of(dest).lower() == digest:
    with open(sidecar, "w", encoding="utf-8") as f:
        f.write(f"{tag} {digest}\n")
    print(f"{os.path.basename(dest)} already present and verified ({tag}).")
    sys.exit(0)

url = asset["browser_download_url"]
print(f"Fetching release metadata for {repo}@{tag}...")
print(f"Downloading {url} ...")
os.makedirs(os.path.dirname(dest), exist_ok=True)
tmp = dest + ".tmp"
try:
    data = fetch(url)
except Exception as exc:
    print(f"Error: download failed ({exc}).", file=sys.stderr)
    sys.exit(1)

actual = hashlib.sha256(data).hexdigest().lower()
if digest:
    if actual != digest:
        if os.path.exists(tmp):
            os.remove(tmp)
        print(f"Error: sha256 mismatch for {dest} (got {actual}, expected {digest}).", file=sys.stderr)
        sys.exit(1)
    print(f"sha256 verified: {actual}")
else:
    digest = actual
    print(f"sha256 computed: {actual}")

with open(tmp, "wb") as f:
    f.write(data)

os.replace(tmp, dest)
with open(sidecar, "w", encoding="utf-8") as f:
    f.write(f"{tag} {digest}\n")
print(f"{os.path.basename(dest)} ready ({tag}): {dest}")
PY
}

if [ -e "$PAYLOAD_SUBMODULE/.git" ]; then
    PAYLOAD_TAG=$(git -C "$PAYLOAD_SUBMODULE" describe --tags --always 2>/dev/null || echo "$DEFAULT_PAYLOAD_TAG")
else
    PAYLOAD_TAG="$DEFAULT_PAYLOAD_TAG"
fi

download_release "$ELFLDR_REPO" "$ELFLDR_TAG" "$ELFLDR_DEST"
download_release "$PAYLOAD_REPO" "$PAYLOAD_TAG" "$PAYLOAD_DEST"
