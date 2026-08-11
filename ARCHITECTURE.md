# PS5 WebKit Autoloader: Architecture & Project Overview

This document is designed to give developers a comprehensive overview of how the **PS5 WebKit Autoloader (WKAL)** project is structured, its goals, and how its various components interact.

## Core Purpose
The goal of this project is to provide a reliable, persistent, and visually polished entry point
for PS5 payloads (specifically targeting WebKit exploits).

Because the PS5 browser is locked down, WebKit exploits are normally triggered by pointing the
console's DNS at an exploit host and opening the PlayStation User's Guide. This project removes
that daily step, and it can be set up in one of two ways depending on whether the console is
already jailbroken:

1. **Already jailbroken — load the installer ELF.** Send `webkit-autoloader-installer_v*.elf` to
   the console (elfldr or Payload Manager). It creates the permanent `WKAL00001` homescreen
   shortcut and caches the frontend via the browser's AppCache.
2. **Not jailbroken yet — use the PC Host.** Run the host script on a PC (a single self-contained
   Python 3 script — no pip packages — or the Windows `.exe` built by GitHub Actions; `openssl`
   is required at runtime for the HTTPS certificate), point the PS5's DNS at it, and open the
   User's Guide. It spoofs `manuals.playstation.net` (DNS + self-signed HTTPS), serves the same
   frontend, runs the WebKit exploit, and loads the **installer ELF** automatically.

Both paths end at the same place: the **WebKit Autoloader** homescreen app, which from then on
runs fully offline — it runs the exploit chain and autoloads the real `payload.elf`
(unified-autoloader). Both paths embed the identical `frontend/autoloader/` UI; only the loaded
payload differs — the installer ELF during setup, the unified-autoloader payload from the
homescreen.

---

## 1. The Frontend Payload (`frontend/autoloader/`)
This is the core WebKit Autoloader UI. It contains the HTML, CSS, and JS that the user actually sees on their PS5.
- It is served by both the ELF and the PC Host.
- The page is a loader shell: a startup splash (logo + title, animated out after ~1.5s), a monospace log terminal, a progress bar, and a bottom-centered footer with the version/build-time and an open-source notice.
- The exploit itself runs in a same-origin **iframe** (`#exploit`, visible bottom-right for debugging) pointing at slopkit's `poops.html` with an `?autoload=<payload>` query param (see [slopkit integration](#6-slopkit-integration-and-the-patch-workflow)). `app.js` mirrors slopkit's live screen (`#scr`), stage (`#stage`), early log (`#early`) and summary (`#summary`) into the log terminal, so the UI shows exactly what the chain is doing — plus the `?autoload` result posted back via `postMessage`.
- `index.html` carries the full build version both in its `<title>` and in the visible `<footer>` via the `[[VERSION_PLACEHOLDER]]`/`[[BUILD_TIME_PLACEHOLDER]]` tokens (replaced at build time — see [Versioning](#5-versioning)).
- A full-screen `#testGate` overlay (test-build builds only) shows the "THIS IS A TEST BUILD / UNTESTED, MAY NOT WORK" banner with a GitHub Discussions QR invite. The exploit only starts after the user presses **Continue** and the splash has fully faded out — `app.js` sets the iframe `src` only then, and the log mirror stays inert until the gate is accepted (`chainStarted`).
- **Important**: It does *not* contain caching logic itself. Caching is handled exclusively by the ELF's wrapper page (`installer-page`).

---

## 2. The Native App Installer (`src/` and `frontend/installer-page/`)
The native installer is a PS5 payload compiled into an `.elf` binary using the PS5 Payload SDK.

### How it works:
1. The user sends `installer.elf` to their jailbroken PS5 (usually via port 9021).
2. The ELF runs natively on the PS5 and creates a fake homescreen application (`WKAL00001`).
3. The ELF spins up an internal C-based HTTP server (using `libmicrohttpd`) on port 18181.
4. The server hosts the `frontend/dist/` directory, which contains:
   - `installer-page/index.html`: A wrapper UI that initiates the caching process.
   - `cache.appcache`: The manifest file that tells the PS5 browser to save the files offline.
   - `app/`: The actual `frontend/autoloader/` files.
   The frontend files are embedded **compressed** (raw DEFLATE, via the vendored `src/inflate.c` — puff.c) and inflated on demand when served; `gen_file_registry.py` emits the compressed registry.
5. The ELF programmatically launches the PS5 browser, pointing it to the internal server (URL carries `?v=<version>` so the browser never serves a stale AppCache master entry). The browser caches the files, hits a `/cache_complete` endpoint, and the ELF cleanly shuts down.
6. The installed homescreen app's `deeplinkUri` points at `http://127.0.0.1:18181/app/index.html` — the cached autoloader page — so launching it later serves the offline UI directly (no intermediate wrapper flash). A reboot after installing is recommended so the exploit chain runs fresh from a clean boot.
7. From then on, the user simply launches the "WebKit Autoloader" from their homescreen, and it loads the cached UI perfectly offline.

---

## 3. The PC Host (`pc-host/host.py` -> `webkit-autoloader-host_v{version}.py` / `.exe`)
For users who are not yet jailbroken and need to use a WebKit exploit to run payloads (like installing the homescreen app itself), this Python script provides the necessary network-based entry point.

### How it works:
1. The script runs on the user's PC. It binds ports 53 (DNS) and 443 (HTTPS) — both are mandatory. A plain-HTTP server is **not** required and is only started when explicitly requested via `--http-port` (e.g. for testing the page in a desktop browser).
2. **DNS Spoofing**: It intercepts DNS requests. Any request for `manuals.playstation.net` is redirected to the PC's IP address. All other PlayStation telemetry domains are blocked (returning `NXDOMAIN`).
3. **HTTPS Bridging**: It runs an HTTPS server on port 443 (required) with an in-memory, self-signed SSL certificate generated on the fly to seamlessly bypass the PS5's strict HTTPS requirements for the User's Guide. If port 443 is unavailable, the script exits with an error; an unavailable optional HTTP port only prints a warning.
4. **URL Interception**: The PS5 requests language-specific URLs (e.g., `/document/en/ps5/`). The script intercepts these and transparently maps them to the root of the payload.
5. **Fat Binary (Embedded Payload)**: The `build_host.py` tool merges the `frontend/autoloader/` and `pc-host/overrides/` directories, compresses them into a zip file, encodes them in Base64, and injects them directly into the Python script. Unused slopkit assets (its bundled payload servers, readme.png) and the throwaway `.git` repo are filtered out at build time.
6. When the script runs, it serves the frontend assets *directly from memory*, requiring zero external files.
7. **Installer payload**: the PC host is the one-time setup flow, so it serves the **installer ELF** as the autoload payload (`payloads/payload.elf` in the zip is replaced by the built `installer.elf` via `--payload`, see the Makefile's `HOST_PAYLOAD`).
8. The banner shows the full build version (`INSTALLER-HOST v{version}`), injected by `build_host.py` at build time — see [Versioning](#5-versioning).

---

## 4. Build System & CI/CD
The project employs a robust build system to generate artifacts for both pathways.

- **`Makefile`**: The central orchestrator. It regenerates the version header, runs `slopkit-prepare` (see below), stages the frontend files, generates C headers for the embedded ELF files (`tools/gen_file_registry.py`), and invokes the compiler. `make print-version` prints the current full version. `make dev` runs `tools/dev_server.py`, a zero-dependency local server that serves `frontend/autoloader/` with the same `/app/` path mapping and version-token injection as the real build — for quick browser previews.
- **`tools/gen_file_registry.py`**: walks `frontend/dist/`, filters out unused files (slopkit's bundled payload servers, `readme.png`, the throwaway `.git`), **compresses** each remaining file (raw DEFLATE) and emits `include/file_registry.{h,c}`. The server inflates on demand via `src/inflate.c`.
- **`build_release.sh`**: A wrapper that spins up a Dockerized PS5 SDK environment to cleanly build the ELF without requiring the user to install the SDK locally. It also runs `make host HOST_PAYLOAD=...` to generate the fat versioned `webkit-autoloader-host_v{version}.py` script (embedding the versioned installer ELF), and renames the ELF to `webkit-autoloader-installer_v{version}.elf`.
- **GitHub Actions (`.github/workflows/release.yml`)**: Automates the release process with `BUILD_TYPE=stable`. It builds the ELF (via Ubuntu Docker), the Python script, and then passes the Python script to a `windows-latest` runner to compile it into a standalone `.exe` using PyInstaller.

## 5. Versioning
Driven by `tools/gen_version.py`: the base version lives in `include/wkali.h`. Dev builds use `<base>-dev-<suffix>` (suffix = short git hash, or a timestamp when the tree is dirty); stable builds (`env BUILD_TYPE=stable`, default `dev`) use the bare `<base>` with no hash/timestamp suffix. The result goes into the gitignored `include/wkali_version.h` (`WKAL_FULL_VERSION` etc., only rewritten on change) and is propagated everywhere:

- **ELF installer**: startup log, `WKALI_VER:` binary signature, success notification, `/version` route, artifact name `webkit-autoloader-installer_v{version}.elf`.
- **Installer page**: version/build-time tokens in the `<title>` (`frontend/installer-page/index.html`).
- **Autoloader page**: `[[VERSION_PLACEHOLDER]]`/`[[BUILD_TIME_PLACEHOLDER]]` in the `<title>` and the bottom `<footer>` (`frontend/autoloader/index.html`).
- **PC host**: banner rows `INSTALLER-HOST v{version}` and `by PLK (built {build_time})`, artifact names `webkit-autoloader-host_v{version}.py` / `.exe`.

`gen_file_registry.py` replaces the placeholders for the ELF-embedded copies (`/index.html`, `/app/index.html`); `build_host.py` replaces them in the zipped autoloader and injects the version into the script.

---

## 6. Slopkit Integration and the Patch Workflow

The WebKit exploit chain is [slopkit](https://github.com/jordyidk/slopkit), pinned as a pristine git
submodule at `third_party/slopkit/`. It is **never modified in place**. All of our integration
changes live in `tools/slopkit-autoload.patch`, which is applied to a throwaway copy.

### First-time setup

```bash
git submodule update --init --recursive
make dev       # copies + patches slopkit automatically, then serves the frontend
```

### The copy + patch pipeline (`tools/apply_slopkit_patch.sh`)

The build needs slopkit under `frontend/autoloader/slopkit/` (gitignored — see `.gitignore`).
The Makefile runs `slopkit-prepare` automatically before staging, host builds and `make dev`:

1. **Fresh copy**: `third_party/slopkit` → `frontend/autoloader/slopkit` (repo metadata stripped).
2. **Throwaway git repo**: `git init` + commit "slopkit pristine". This lets `git apply` handle
   binary diffs (the deleted `mmhmm-cats-ps5.gif`) — plain `git apply` on a non-repo dir cannot.
3. **Apply the patch**: `tools/slopkit-autoload.patch` is applied and committed as
   "Apply WKAL autoloader patch" (author `wkal <wkal@localhost>`).

### What the patch does (all additive, in `slopkit/slopkit/poops.html`)

- Adds an `?autoload=<name>` query param. After the chain finishes and elfldr is up, slopkit
  waits 4 s (for elfldr to accept connections on port 9021) and auto-sends the payload from
  `../../payloads/<name>` — our own `frontend/autoloader/payloads/`, keeping the submodule pristine.
- Adds a hidden payload-menu tile so `payloadIsListed()` passes.
- Raises `PAYLOAD_MAX_SIZE` to 4 MiB (the bundled payloads are larger than slopkit's 2 MiB default).
- Posts `{type:"wkal", kind:"autoload", ok, bytes}` to the parent page for the UI.
- Removes the ~1 MB cat gif (preload, image, `setCatResult` simplified).

### Updating slopkit

```bash
git submodule update --remote third_party/slopkit
tools/apply_slopkit_patch.sh     # re-applies the patch; errors if upstream changed the patched files
```

If the patch no longer applies, regenerate it with `git -C third_party/slopkit diff > tools/slopkit-autoload.patch`.

### Bundled payload (`scripts/download_deps.sh`)

The bundled payload (`frontend/autoloader/payloads/payload.elf`) is the `ps5-unified-autoloader`
ELF used by the homescreen flow. It is not rebuilt locally — it is downloaded from the
`third_party/ps5-unified-autoloader` submodule's pinned GitHub release by
`scripts/download_deps.sh` (run automatically as the Makefile's `payload-deps` target before
staging, host builds and `make dev`), sha256-verified against the release digest, and cached in
a `.sha256` sidecar so offline rebuilds work. Bump the submodule to pick up a newer release.

---

## Key Conventions
When modifying this project, keep the following in mind:
- **Changing the UI**: Edit files in `frontend/autoloader/`. These changes will automatically propagate to both the ELF and the PC Host on the next build.
- **Bumping the version**: Change `WKAL_VERSION` in `include/wkali.h` and rebuild — `tools/gen_version.py` regenerates the full version everywhere (see [Versioning](#5-versioning)).
- **Path Resolution**: The ELF serves the autoloader at `/app/`. The PC Host intercepts `/app/` paths and maps them to the root. If you add new asset paths in the HTML, be aware of this mapping.
- **Caching**: Never put `manifest="/cache.appcache"` in the `autoloader/index.html`. Caching is strictly the domain of `installer-page/index.html` during the ELF installation phase.
- **PC Host Logic**: If you modify `host.py`, you must run `make host` (or `build_release.sh`) to inject the payload and generate the final `webkit-autoloader-host_v{version}.py`.
- **Slopkit changes**: Never edit `third_party/slopkit/` or the generated `frontend/autoloader/slopkit/` directly — edit `tools/slopkit-autoload.patch` (or regenerate it) instead.
