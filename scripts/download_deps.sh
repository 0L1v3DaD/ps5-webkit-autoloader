#!/usr/bin/env bash
# Download the ps5-unified-autoloader payload ELF from its GitHub release,
# pinned to the version of the third_party/ps5-unified-autoloader submodule.
#
# The payload is the "bundled" ELF embedded in the installer: after install,
# the homescreen app runs the exploit chain and autoloads it from the local
# AppCache. It is not rebuilt here — it ships as a prebuilt release asset of
# itsPLK/ps5-unified-autoloader (same approach as ps5-y2jb-autoloader's
# scripts/download_deps.sh), but pinned to the submodule commit so builds are
# reproducible: bump the submodule to bump the payload.
#
# Idempotent: skips when the payload already exists and its sha256 matches
# the release digest. The Makefile runs this automatically (payload-deps)
# before staging the frontend and building the PC host.
#
# Uses only python3 (a build dependency already) — no curl required, so it
# also runs inside the Docker SDK image.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE="$ROOT/third_party/ps5-unified-autoloader"
DEST_DIR="$ROOT/frontend/autoloader/payloads"
DEST="$DEST_DIR/payload.elf"
REPO="itsPLK/ps5-unified-autoloader"

if [ ! -e "$SUBMODULE/.git" ]; then
    echo "Error: ps5-unified-autoloader submodule is not initialised."
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

TAG=$(git -C "$SUBMODULE" describe --tags --always)

# Fetch the pinned release, verify the payload, and download it if needed.
# Exit codes: 0 = payload ready, 3 = payload already present and verified.
python3 - "$REPO" "$TAG" "$DEST" <<'PY'
import hashlib
import json
import os
import sys
import urllib.request

repo, tag, dest = sys.argv[1], sys.argv[2], sys.argv[3]
sidecar = dest + ".sha256"  # "<tag> <sha256>" cached after a successful verify

def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

# Offline fast path: payload + sidecar from a previous successful run.
if os.path.isfile(dest) and os.path.isfile(sidecar):
    with open(sidecar) as f:
        try:
            st_tag, st_hash = f.read().split()
        except ValueError:
            st_tag, st_hash = "", ""
    if st_tag == tag and sha256_of(dest) == st_hash:
        print(f"ps5-unified-autoloader payload already present and verified ({tag}).")
        sys.exit(0)
    print("Existing payload does not match the pinned release - re-checking...")

def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "ps5-webkit-autoloader-build"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()

try:
    release = json.loads(fetch(f"https://api.github.com/repos/{repo}/releases/tags/{tag}"))
except Exception as exc:
    print(f"Error: could not fetch release {tag} ({exc}).", file=sys.stderr)
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
digest = digest.split(":", 1)[-1] if ":" in digest else digest

# Already downloaded and matching the pinned release? Just cache the digest.
if os.path.isfile(dest) and digest and sha256_of(dest) == digest:
    with open(sidecar, "w") as f:
        f.write(f"{tag} {digest}\n")
    print(f"ps5-unified-autoloader payload already present and verified ({tag}).")
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
with open(tmp, "wb") as f:
    f.write(data)

if digest:
    actual = hashlib.sha256(data).hexdigest()
    if actual != digest:
        os.remove(tmp)
        print(f"Error: sha256 mismatch (got {actual}, expected {digest}).", file=sys.stderr)
        sys.exit(1)
    print(f"sha256 verified: {actual}")

os.replace(tmp, dest)
with open(sidecar, "w") as f:
    f.write(f"{tag} {digest}\n")
print(f"ps5-unified-autoloader payload ready ({tag}): {dest}")
PY
