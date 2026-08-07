# PS5 WebKit Autoloader: Architecture & Project Overview

This document is designed to give developers a comprehensive overview of how the **PS5 WebKit Autoloader (WKAL)** project is structured, its goals, and how its various components interact.

## Core Purpose
The goal of this project is to provide a reliable, persistent, and visually polished entry point for PS5 payloads (specifically targeting WebKit exploits). 

Because the PS5 browser is locked down, users typically have to navigate through network settings to trigger an exploit host. This project solves that by offering **two distinct methods** for launching the autoloader:
1. **The Native App (ELF Installer)**: A permanent homescreen shortcut (`WKAL00001`) that runs offline via the browser's AppCache.
2. **The PC Host (Spoofing Script)**: A zero-dependency script run on a PC that spoofs the PlayStation User's Guide to serve the exact same payload over the network.

Both methods ultimately serve the exact same frontend payload (`frontend/autoloader/`), ensuring a unified experience.

---

## 1. The Frontend Payload (`frontend/autoloader/`)
This is the core WebKit Autoloader UI. It contains the HTML, CSS, and JS that the user actually sees on their PS5.
- It is designed to be completely standalone.
- It is served by both the ELF and the PC Host.
- The page is a loader shell: a startup splash (logo + title, animated out after ~1.5s), a monospace log terminal, a progress bar, and a bottom-centered footer with the version/build-time and an open-source notice. The exploit steps behind it are stubbed demo functions (`runWebkitExploit`/`runKernelExploit`/`runPayload` in `app.js`) that log and advance the progress bar with sample timeouts, so the real WebKit exploit can be dropped in later without restructuring.
- `index.html` carries the full build version both in its `<title>` and in the visible `<footer>` via the `[[VERSION_PLACEHOLDER]]`/`[[BUILD_TIME_PLACEHOLDER]]` tokens (replaced at build time — see [Versioning](#5-versioning)).
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
5. The ELF programmatically launches the PS5 browser, pointing it to the internal server. The browser caches the files, hits a `/cache_complete` endpoint, and the ELF cleanly shuts down.
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
5. **Fat Binary (Embedded Payload)**: The `build_host.py` tool merges the `frontend/autoloader/` and `pc-host/overrides/` directories, compresses them into a zip file, encodes them in Base64, and injects them directly into the Python script.
6. When the script runs, it serves the frontend assets *directly from memory*, requiring zero external files. 
7. The banner shows the full build version (`INSTALLER-HOST v{version}`), injected by `build_host.py` at build time — see [Versioning](#5-versioning).

---

## 4. Build System & CI/CD
The project employs a robust build system to generate artifacts for both pathways.

- **`Makefile`**: The central orchestrator. It regenerates the version header, stages the frontend files, generates C headers for the embedded ELF files (`tools/gen_file_registry.py`), and invokes the compiler. `make print-version` prints the current full version. `make dev` runs `tools/dev_server.py`, a zero-dependency local server that serves `frontend/autoloader/` with the same `/app/` path mapping and version-token injection as the real build — for quick browser previews.
- **`build_release.sh`**: A wrapper that spins up a Dockerized PS5 SDK environment to cleanly build the ELF without requiring the user to install the SDK locally. It also runs `tools/build_host.py` to generate the fat versioned `webkit-autoloader-host_v{version}.py` script, and renames the ELF to `webkit-autoloader-installer_v{version}.elf`.
- **GitHub Actions (`.github/workflows/release.yml`)**: Automates the release process with `BUILD_TYPE=stable`. It builds the ELF (via Ubuntu Docker), the Python script, and then passes the Python script to a `windows-latest` runner to compile it into a standalone `.exe` using PyInstaller.

## 5. Versioning
Driven by `tools/gen_version.py`: the base version lives in `include/wkali.h`. Dev builds use `<base>-dev-<suffix>` (suffix = short git hash, or a timestamp when the tree is dirty); stable builds (`env BUILD_TYPE=stable`, default `dev`) use the bare `<base>` with no hash/timestamp suffix. The result goes into the gitignored `include/wkali_version.h` (`WKAL_FULL_VERSION` etc., only rewritten on change) and is propagated everywhere:

- **ELF installer**: startup log, `WKALI_VER:` binary signature, success notification, `/version` route, artifact name `webkit-autoloader-installer_v{version}.elf`.
- **Installer page**: version/build-time tokens in the `<title>` (`frontend/installer-page/index.html`).
- **Autoloader page**: `[[VERSION_PLACEHOLDER]]`/`[[BUILD_TIME_PLACEHOLDER]]` in the `<title>` and the bottom `<footer>` (`frontend/autoloader/index.html`).
- **PC host**: banner rows `INSTALLER-HOST v{version}` and `by PLK (built {build_time})`, artifact names `webkit-autoloader-host_v{version}.py` / `.exe`.

`gen_file_registry.py` replaces the placeholders for the ELF-embedded copies (`/index.html`, `/app/index.html`); `build_host.py` replaces them in the zipped autoloader and injects the version into the script.

---

## Key Conventions
When modifying this project, keep the following in mind:
- **Changing the UI**: Edit files in `frontend/autoloader/`. These changes will automatically propagate to both the ELF and the PC Host on the next build.
- **Bumping the version**: Change `WKAL_VERSION` in `include/wkali.h` and rebuild — `tools/gen_version.py` regenerates the full version everywhere (see [Versioning](#5-versioning)).
- **Path Resolution**: The ELF serves the autoloader at `/app/`. The PC Host intercepts `/app/` paths and maps them to the root. If you add new asset paths in the HTML, be aware of this mapping.
- **Caching**: Never put `manifest="/cache.appcache"` in the `autoloader/index.html`. Caching is strictly the domain of `installer-page/index.html` during the ELF installation phase.
- **PC Host Logic**: If you modify `host.py`, you must run `make host` (or `build_release.sh`) to inject the payload and generate the final `webkit-autoloader-host_v{version}.py`.
