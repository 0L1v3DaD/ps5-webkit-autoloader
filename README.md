<p align="center">
 <img src="./assets/icon.svg" width="128" />
</p>
<h1 align="center">PS5 WebKit Autoloader</h1>
&nbsp;
<p align="center">Automatically loads the WebKit exploit and your elf payloads.<br><b>Pre-alpha:</b> firmware compatibility not yet verified.</p>

<p align="center">
    <b>Other Autoloaders:</b><br>
    <a href="https://github.com/itsPLK/ps5-y2jb-autoloader">Y2JB</a> |
    <a href="https://github.com/itsPLK/ps5-bdjb-autoloader">BD-JB</a> |
    <a href="https://github.com/itsPLK/ps5-lua-autoloader">Lua</a>
</p>

## Why WebKit Autoloader?

WebKit exploits are usually loaded by pointing your PS5's DNS at some server hosted by someone on the internet. That means you're putting your trust in whoever runs that server — and if it goes down, changes, or disappears, your setup breaks.

This autoloader does it differently:

- **You know exactly what you're loading.** The exploit page and the autoloader are served from your own PC and, after the one-time install, straight from your own PS5 — never from a third-party DNS host.
- **No reliance on anyone's custom DNS servers.** There's nothing external to go down or change behind your back.
- **One-time setup, then a homescreen shortcut.** Once it's installed, you don't need a PC or the network at all — just launch "WebKit Autoloader" from the homescreen and you're done.
- **Payloads loaded the way you already know.** After the exploit chain runs, your payloads are sent just like in [Y2JB](https://github.com/itsPLK/ps5-y2jb-autoloader) / [BD-JB](https://github.com/itsPLK/ps5-bdjb-autoloader) / [Lua](https://github.com/itsPLK/ps5-lua-autoloader) autoloaders — via **Payload Manager**, or a custom `autoload.txt`.

## How it works

1. **PC Host (custom DNS, one-time)** — run `webkit-autoloader-host.py` on your PC and point your PS5's DNS at it. Opening the "User's Guide" loads the WebKit exploit page directly from your PC (`manuals.playstation.net` is intercepted locally — no third-party host involved). The page runs the exploit and loads **only** the installer payload, which installs the `WKAL00001` "WebKit Autoloader" homescreen app. Nothing else is loaded in this session.
2. **Reboot once** — the exploit should always run fresh from a clean boot. After the installer finishes, reboot the console so the homescreen shortcut can run the exploit chain cleanly.
3. **Homescreen shortcut (from now on)** — that's it, you never need the DNS setup again. Every next time, you just launch **WebKit Autoloader** from the homescreen: it loads fully offline, runs the WebKit/kernel exploit chain, and loads your payloads — [Payload Manager](https://github.com/itsPLK/ps5-payload-manager) by default, or a custom [`autoload.txt`](#option-2-manual-config-autoloadtxt) config.

## Setup Instructions

There are two ways to set up the autoloader, depending on whether you're already jailbroken.

### 🟢 Already jailbroken? Just load the installer ELF

1. Download `webkit-autoloader-installer_vX.Y.Z.elf` from the [Releases](https://github.com/itsPLK/ps5-webkit-autoloader/releases) page.
2. Send it to your PS5 with `elfldr`, or launch it from Payload Manager.
3. The installer creates the **WebKit Autoloader** app on the homescreen, opens the browser once to cache the autoloader page, and exits.
4. **Reboot once** — then launch **WebKit Autoloader** from the homescreen from now on. Everything runs offline on the console itself — no PC, no DNS changes, nothing to keep running.

### ⚙️ Not jailbroken yet

This is the classic WebKit way of getting in, but served from your own PC instead of a third-party DNS host:

1. Download `webkit-autoloader-host.py` (or the Windows `.exe`) from the [Releases](https://github.com/itsPLK/ps5-webkit-autoloader/releases) page.
2. Run it on a PC on the same network as your PS5.
3. On your PS5, set your network's DNS server to your PC's IP address.
4. On your PS5, open the **User's Guide** from Settings. The **WebKit Autoloader** page loads from your PC — it runs the exploit and loads **only** the installer, which adds the **WebKit Autoloader** app to your homescreen (no payloads are autoloaded in this session).
5. **Reboot your PS5**, then launch **WebKit Autoloader** from the homescreen. From now on you don't need the PC Host at all — the shortcut runs the full exploit chain and autoloads your payloads offline.

## How to Use

There are two ways to configure payloads:

### 🟢 Option 1: Payload Manager

If no `autoload.txt` config is found, the autoloader will automatically launch **[Payload Manager](https://github.com/itsPLK/ps5-payload-manager)** — a fully-featured PS5 payload manager with a web UI. This lets you configure and send payloads directly from your browser, without needing to manually set up config files or transfer ELF files ahead of time.

Just run the autoloader — if there's nothing configured, Payload Manager starts automatically.

> **Note:** Payload Manager also has its own built-in autoload feature, which lets you configure payloads to load automatically on startup — all managed through its web UI. This is separate from the `autoload.txt` mechanism described below.

---

### ⚙️ Option 2: Manual Config (`autoload.txt`)

For a fixed, automated payload chain, you can configure payloads manually:

- Create a directory named `ps5_autoloader`.
- Inside this directory, place your `.elf` / `.bin` files, and an `autoload.txt` file.
  - In `autoload.txt`, list the files you want to load, one filename per line.
  - Filenames are case-sensitive — ensure each name exactly matches the file.
  - You can add lines like `!1000` to make the loader wait 1000 ms before sending the next payload.
- Put the `ps5_autoloader` directory in one of these locations (priority order - highest first):
  - Root of a USB drive
  - Internal drive: `/data/ps5_autoloader`

> **Note:** When an `autoload.txt` config is found, Payload Manager is **not** launched automatically. If you also want Payload Manager available, place `pldmgr.elf` in your `ps5_autoloader` directory and add it to `autoload.txt`.

## Additional Info

<Details>
<Summary><i>How to update the autoloader?</i></Summary>

The autoloader content is cached on the console, so updates are just as simple as the initial install:
1. Re-run the latest `webkit-autoloader-installer_vX.Y.Z.elf` from the [Releases](https://github.com/itsPLK/ps5-webkit-autoloader/releases) page.
2. The installer updates the homescreen app and refreshes the cached page.

Your payloads and `autoload.txt` on USB / internal storage are never touched.
</Details>

<Details>
<Summary><i>How to use custom ELF Loader version?</i></Summary>

By default, the autoloader uses a custom version of **elfldr** that only accepts connections from the PS5 itself (localhost). This improves security by preventing other devices on your network from sending payloads to your console.

If you want to use a "normal" ELF Loader that allows sending payloads from any device:
1. Place your custom ELF Loader (e.g. `elfldr.elf`) in the `ps5_autoloader` directory.
2. Add `elfldr.elf` to your `autoload.txt`.
3. **Note**: If you are loading other payloads right after `elfldr.elf` in your `autoload.txt`, add a sleep command immediately after it (like `!4000` to sleep for 4 seconds) to give the new ELF Loader time to start up and listen before subsequent payloads are sent.

Example `autoload.txt`:
```text
# Load custom ELF Loader
elfldr.elf
# Give it 4 seconds to start up (only needed if sending more payloads)
!4000
# Send other payloads
ftpsrv.elf
```
</Details>

---

📚 **For a deep dive into how the native installer and the PC Host work under the hood, check out [ARCHITECTURE.md](ARCHITECTURE.md).**

## Credits

* **[john-tornblom](https://github.com/john-tornblom)** — [ps5-payload-sdk](https://github.com/ps5-payload-dev/sdk/)
* Everyone else contributing to the PS5 homebrew scene.

## Disclaimer

This tool is provided as-is for research and development purposes only. Use at your own risk. The developers are not responsible for any damage, data loss, or consequences resulting from the use of this software.

## License

This project is licensed under the GPL-3.0 License.

## Donate
- [donate to PLK](DONATE.md)
