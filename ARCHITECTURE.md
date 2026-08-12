# PS5 WebKit Autoloader: Architecture

A persistent entry point for PS5 payloads built around the slopkit WebKit/kernel exploit chain.
Two setup paths converge on the same result: a `WKAL00001` homescreen app that runs the exploit
chain and autoloads your payloads fully offline.

## Repository layout

| Path | Purpose |
|---|---|
| `frontend/autoloader/` | The autoloader UI, served by both the installer and the PC host |
| `frontend/installer-page/` | Wrapper page that drives the one-time AppCache caching |
| `pc-host/` | The PC host script (`host.py`) + overrides for the bootstrap flow |
| `src/` | Native installer ELF (HTTP server, app installer, browser launcher) |
| `include/` | Headers, incl. generated `wkali_version.h` and `file_registry.{h,c}` |
| `tools/` | Build/version/icon/registry scripts + the slopkit patch |
| `scripts/` | Dependency download (`download_deps.sh`) |
| `assets/` | Icon source and PS5 app metadata templates |
| `third_party/` | `slopkit` and `ps5-unified-autoloader` submodules (pinned) |

## Two setup flows

**Installer ELF (already jailbroken).** Send `webkit-autoloader-installer_v*.elf` to the console
(elfldr or Payload Manager). It creates the `WKAL00001` app, opens the browser once to cache the
frontend via AppCache, then exits. From then on the app runs the chain offline from the cache.

**PC host (not jailbroken).** Run `webkit-autoloader-host_v*.py` / `.exe` on a PC, point the
console's DNS at it, and open the User's Guide. The host spoofs `manuals.playstation.net`
(DNS + self-signed HTTPS) and serves the same frontend, but autoloads the **installer ELF**
instead of the unified-autoloader — so this flow installs the homescreen app.

## Frontend (`frontend/autoloader/`)

- A splash screen, a log terminal and a progress bar. The exploit runs in a **hidden**
  same-origin iframe pointing at slopkit's `poops.html?go=1&auto=1&...&autoload=payload.elf`.
- On `window.load` the iframe is armed; at script parse it is blanked to `about:blank` so a
  WebProcess-crash page restore never auto-runs the chain. Before arming, `clearSlopkitState()`
  removes slopkit's one-shot latch and "stopped at …" markers from sessionStorage so every
  launch restarts the full ladder.
- `app.js` mirrors the chain's screen/stage/early/summary into the log (errors, stage changes
  and summary verdicts) and receives the `?autoload` result via `postMessage`.

`payload.elf` is a virtual name: the PC host serves the installer ELF there, the homescreen app
serves the real unified-autoloader.

## Native installer (`src/`)

A PS5 payload running a `libmicrohttpd` server on port **18181**:

1. Serves the staged frontend: installer-page at `/`, the autoloader at `/app/`.
2. Frontend files are embedded **compressed** (raw DEFLATE via `src/inflate.c`, the vendored
   puff) and inflated on demand.
3. The browser caches everything through `cache.appcache`, then hits `/cache_complete`, and the
   ELF shuts down. The master URL carries `?v=<version>` so stale cached entries are avoided.
4. The app's `deeplinkUri` is `http://127.0.0.1:18181/app/index.html` — the cached page.

## PC host (`pc-host/host.py`)

- Binds DNS port 53 and HTTPS port 443 (both required). A self-signed certificate is generated
  on the fly with `openssl`.
- Redirects `manuals.playstation.net` to the PC and blocks other telemetry domains; the User's
  Guide URL is mapped to the served frontend.
- The frontend (+ filtered slopkit assets) is embedded in the script as a base64 zip and served
  from memory. `HOST_PAYLOAD` replaces the autoload payload with the installer ELF.

## Build system

- `make`: `all` (ELF), `host` (standalone host script), `dev` (local preview server),
  `slopkit-prepare`, `payload-deps`, `version`, `icons`, `clean`.
- `tools/gen_file_registry.py` walks the staged `frontend/dist/`, compresses each file (raw
  DEFLATE) and emits the C registry + the AppCache manifest. Unused slopkit payloads and assets
  are filtered out.
- `build_release.sh` builds the ELF in a Dockerized SDK and the host script; CI
  (`.github/workflows/release.yml`) produces the versioned artifacts and the Windows `.exe`.

## Slopkit integration

`slopkit` is a pinned, **pristine** submodule. The build copies it to the gitignored
`frontend/autoloader/slopkit/` and applies `tools/slopkit-autoload.patch` there
(`tools/apply_slopkit_patch.sh`, run automatically by the Makefile).

The patch (all in `slopkit/slopkit/poops.html`):

- `?autoload=<name>`: after the chain finishes and elfldr is up, sends the named payload from
  `../../payloads/`.
- A hidden menu tile so `payloadIsListed()` accepts the payload, and `PAYLOAD_MAX_SIZE` raised
  to 4 MiB.
- Posts `{type:"wkal", kind:"autoload", ok, bytes}` to the parent page.
- Removes the ~1 MB cat gif.

To update slopkit: `git submodule update --remote third_party/slopkit`, re-run the script, and
regenerate the patch if it no longer applies
(`git -C third_party/slopkit diff > tools/slopkit-autoload.patch`).

## Payload dependency

`scripts/download_deps.sh` (the Makefile's `payload-deps` target) downloads
`frontend/autoloader/payloads/payload.elf` from the `ps5-unified-autoloader` submodule's pinned
GitHub release, sha256-verifies it, and caches the digest in a `.sha256` sidecar so offline
rebuilds work. Bump the submodule to pick up a newer release.

## Versioning

The base version lives in `include/wkali.h` (`WKAL_VERSION`). `tools/gen_version.py` produces
the full version — `<base>` for stable (`BUILD_TYPE=stable`) or `<base>-dev-<suffix>` for dev —
and regenerates `include/wkali_version.h`, `assets/param.json` and the version placeholders in
the pages. It ends up in the installer ELF, the host banner and the artifact names.

## Conventions

- The ELF serves the autoloader at `/app/`; the PC host maps `/app/` to its root.
- Never put `manifest="..."` on the autoloader page — caching is the installer page's job.
- Never edit `third_party/slopkit/` or the generated `frontend/autoloader/slopkit/` — edit the
  patch file instead.
- After changing `host.py`, rebuild the host (`make host` / `build_release.sh`).
