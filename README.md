# Quest 2 + Steam Link over USB on a Linux host

**Status: verified 2026-10-05. Depends on three betas (SteamVR 2.18.x beta + Steam Link beta + Steam client beta) — re-verify after every Valve update.**

Official Steam documentation for USB-tethered Quest streaming covers Windows and macOS only. This repo documents what it actually takes to run **Steam Link over USB (NCM) on a Linux host with a Quest 2**, including the three non-obvious root causes that bite you on Linux — none of which are in any Valve or Meta documentation.

It is **not** a tutorial for "how to connect a Quest over USB" — that part is official and works out of the box. It is the recovery guide for the specific failures that happen once you are on Linux, plus the network plumbing that lets the USB link and your PC's internet coexist.

## TL;DR

| Problem | Symptom | Root cause | Fix |
|---|---|---|---|
| SteamVR refuses to start the compositor | error 450 / -201, `timeout - vrcompositor process is not running`, ~21 s watchdog abort, compositor dies with **zero log** | launching Steam with `STEAM_RUNTIME=0` prevents `steam-runtime-launcher-service` from starting; the compositor launch then fails at the bus connection | start Steam with the runtime **enabled** (normal "Steam" entry), then `sudo setcap CAP_SYS_NICE=eip ~/.local/share/Steam/steamapps/common/SteamVR/bin/linux64/vrcompositor-launcher` |
| Video arrives but is **corrupted / garbled** | Steam desktop visible in the headset but full of macro blocking; resets, `HandleUnrecoverableError`, stream reset loops | a *valid* `DRI_PRIME` in the Steam client environment steers the compositor + vrlink Vulkan video encoder onto the dGPU; on this hardware the RADV Vulkan video encode path produces corrupt output. `DRI_PRIME=0` is invalid and is ignored, so SteamVR picks its own GPU — which works | start Steam with `DRI_PRIME=0` (see `wrappers/steam-igpu.sh`) |
| App stays on "connecting…" forever | discovery works (app finds the PC) but no video; PC side shows a real IPv4 on the NCM interface | when the PC's NCM interface holds a real IPv4 address, the Steam client only announces over IPv4; the transport path is **pure IPv6 link-local**, so no v6 path is ever built | keep the PC NCM interface v6-only (no IPv4); the Steam Link app itself configures the headset side (`10.86.13.37/29` static, no gateway) |
| PC loses internet the moment you plug in the Quest | NetworkManager activates a profile on the new `enx*` interface and takes the default route | the auto-generated NM profile for the NCM interface has no never-default setting | `unmanaged-devices=interface-name:enx*` + udev + `ncm-up` service (included) |
| (Docker users) NCM data link never registers, video dead but audio works | `SVLDataLinkUber … list is full` in the vrserver log | vrlink enumerates every local interface into a capped table with no dedup; Docker's v6 bridge/veth entries fill it before NCM gets listed | `91-docker-no-v6.rules` (included) — veth/br-* interfaces go v4-only |

## What is verified, precisely

- NCM interface on the Linux host (`cdc_ncm`, renamed `enx<mac>`) — up and stable across replug. **The NCM MAC changes on every Quest boot**, so all tooling here auto-detects.
- App-side: the Steam Link app switches the USB to NCM on its own (`BTrySetupUSBNetwork` in logcat) and sets `10.86.13.37/29` on the headset `usb0` — no DHCP, no NAT needed on the headset side.
- Transport measured over the USB/NCM path: discovery (UDP 27036 + mDNS 5353 + IPv6 multicast), video **UDP 10400**, control **UDP 39803**, **zero IPv4 packets**. Measured throughput on Wi-Fi: ~17–21 MB/s; USB NCM measured: 0.7 ms RTT, ~756 Mbit/s (headset-storage bound, not the cable).
- PC internet coexists with the NCM link (never-default behavior of the unmanaged interface).
- Audio streams over the USB link; video streaming verified working with the DRI_PRIME fix (no corruption).
- **Honest caveat:** the current beta still hard-depends on Wi-Fi for the *video* channel (error 616 = the app's Wi-Fi status check; Wi-Fi-first discovery is a known rough edge). Pure USB-only video streaming is waiting on Valve. What this repo gives you: a working NCM/USB registration that coexists with your network, no more compositor death, no more garbled video, and a self-healing interface that survives replug.

## Requirements

- Quest 2 on Horizon OS 2.5+ (2.6/2.7 confirmed), Developer Mode enabled
- **Three betas, all opted in:** SteamVR beta (2.18.x), Steam Link app beta (headset), Steam client beta (PC)
- A quality USB 3 data cable (a cheap VR-link cable will hiccup periodically)
- Linux with a working `cdc_ncm` kernel module (all major distros)
- Steam + SteamVR installed and running

## One-time setup

```bash
sudo ./scripts/ncm-install.sh
```

This installs:

- `config/90-ncm-unmanaged.conf` → `/etc/NetworkManager/conf.d/` — NM stops managing `enx*`, so the NCM interface can never steal your default route.
- `config/90-ncm-up.rules` → `/etc/udev/rules.d/` — brings a new `cdc_ncm` interface up immediately on plug.
- `config/91-docker-no-v6.rules` → `/etc/udev/rules.d/` — (Docker users) veth/br-* go v4-only so they stop filling the `SVLDataLinkUber` table.
- `config/ncm-up.service` → enabled systemd service — checks for `cdc_ncm` interfaces every 3 s and brings any DOWN one up. Survives replug and app re-toggling of USB; enabled at boot.

Then, once per machine (and **again after every SteamVR update**):

```bash
sudo setcap CAP_SYS_NICE=eip ~/.local/share/Steam/steamapps/common/SteamVR/bin/linux64/vrcompositor-launcher
```

Start Steam with the included wrapper (not the normal "Steam" entry if your environment carries a valid `DRI_PRIME`):

```bash
./wrappers/steam-igpu.sh   # DRI_PRIME=0 + -cef-disable-gpu + -pipewire, runtime enabled
```

## Per-session flow

1. Plug the Quest in via USB.
2. Launch (or focus) the Steam Link app on the Quest — it switches USB to NCM on its own and sets the headset-side static IP.
3. The `ncm-up` service brings the host `enx*` interface up within seconds. No manual steps.
4. Connect from the app. Verify with `./scripts/ncm-verify.sh`.
5. If you ever have to restart SteamVR (e.g. after the data-link table fills): `./scripts/steam-vr-restart.sh` — SIGKILL + restarthelper relaunch clears the table.

## Known beta limitations (not your fault)

- **616 / "not connected to the wifi"** on a Quest 3 report: even with Wi-Fi off and cable connected, the app checks Wi-Fi state. The current beta hard-depends on Wi-Fi for video. Workarounds: keep Wi-Fi on for streaming (measured fine), or use **ALVR** for a deterministic pure-USB path, or wait for Valve.
- **Wi-Fi-first discovery:** cold-start discovery can fail with Wi-Fi off. Pair over Wi-Fi once, then reconnect over USB.
- **Transport preference bug:** NCM connected but SteamVR still uses the Wi-Fi path on some builds. Turning the headset Wi-Fi radio off forces the cable.
- Error 616 disconnects after ~3 min reported on Quest 3 in the wild.

## NCM gotchas (verified dead ends, don't re-tread)

- `adb shell svc usb setFunctions ncm,adb` **never works** — the framework requires exactly one function bit; leave `adb` out (it is OR'd in automatically when USB debugging is on).
- **RNDIS does not exist on this hardware** — the gadget HAL rejects it and falls back to charge-only. NCM is the only network gadget.
- The `Tethering: ERROR could not enable IpServer for function NCM` line in logcat is a **red herring** — the build's tetherable-NCM regex list is empty; the working path is the Ethernet service, not tethering.
- **Any active VpnService silently swallows the connection** — all status checks report success while traffic never reaches the cable. If the app can't find the PC, kill the VPN first.

## Non-VR (Steam Link app game mode) low FPS on Wayland

Symptom: VR works, non-VR game mode is capped low, monitor shows full FPS, headset 120 Hz setting has no effect. Cause: on a Wayland session the Steam client cannot do desktop capture without `-pipewire`, so streaming falls back to a rate-limited X11/Xwayland grab (the client log says it all: `WARNING: Desktop capture unavailable, try running Steam with -pipewire`). The wrapper above already includes `-pipewire`. Two caveats from upstream:

- **Multi-GPU crash risk** (steamVR-for-Linux #915, open): on iGPU-primary + headless dGPU systems, `-pipewire` can crash SteamVR + client when switching to the desktop tab inside VR. **Re-test the VR path after adding the flag.**
- The 32-bit client needs 32-bit `libEGL`/`libva`/`radeonsi` — check `streaming_log.txt` (or F6 overlay): you want "PipeWire NV12 DMABUF + VAAPI HEVC"; plain `libx264` means the hardware encode fell back to the slow CPU path.

## Verified numbers

- USB NCM: **0.7 ms RTT**, ~756 Mbit/s (headset storage bound)
- Streaming over Wi-Fi: ~17–21 MB/s, 90/120 Hz frametime nominal
- NCM v6 link-local ping: 0.021 ms, 0% loss
- Compositor: alive, `vkCreateVideoSessionParametersKHR` created, no watchdog aborts after the runtime fix

## If it still doesn't work

See [docs/troubleshooting.md](docs/troubleshooting.md) — symptom → root cause → fix, including the compositor zero-log death chain and the variables that were systematically ruled out.

## Maintenance notes

- `setcap` on `vrcompositor-launcher` must be redone after every SteamVR update.
- Docker networks with IPv6 will recreate the data-link table problem — the udev rule handles new veth/br on plug, but existing ones need one cleanup pass (included in `ncm-install.sh`).
- The beta trio changes. Re-verify the whole chain after SteamVR stable catches up; this repo's fixes may become unnecessary.

## Credit & prior art

- `UbootVRC/Wired-Steam-Link-VR` (MIT) — the NCM mechanism teardown and Windows reference; tested on Quest 2 (Android 14).
- `TheDoctorTTV/Wired-Steam-Link-VR-Linux` — the Linux port of the above.
- `kkoemets/quest-vd-wired` — archived once official support landed.
- Upstream issues: steamVR-for-Linux #936 (launcher service / -201), #904 & #965 (AMD encode corruption), #915 (multi-GPU + `-pipewire`).
- UploadVR / vr.org / Road to VR / XR Guidebook — beta mechanics and cable testing.

## License

[MIT](LICENSE)
