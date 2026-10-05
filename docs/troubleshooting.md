# Troubleshooting — symptom → root cause → fix

All entries below were verified on the machine this repo was written for
(Ubuntu, 2×Radeon AI PRO R9700 RDNA4 + Raphael iGPU, GNOME/Wayland,
SteamVR 2.18.x beta, Quest 2). The pattern generalizes; the exact
GPU topology may differ on yours.

## Error 450 / -201: "Host not responding", compositor dies with zero log

**Symptom chain (all of these together):**

- App connects (HMD active in the log), then `VRMsg_StartVRCompositor`
- `Starting vrcompositor process` — then the compositor dies with
  **zero log output**, not even the startup banner
- `Failed Watchdog timeout in thread Connection after ~21s`
- Error 450 / -201, `timeout - vrcompositor process is not running`

The ~21 s is the compositor's fixed startup timeout — it is **not** a
network problem. Audio reaching the headset while video is dead confirms
the transport chain (NCM / data link / app) is fine; the compositor is
the only dead component.

**Root cause:** `steam-runtime-launcher-service` is not running. vrserver
starts the compositor via `steam-runtime-launch-client --alongside-steam`,
which fails with `E: Unable to connect to any of the specified bus names
(is steam-runtime-launcher-service running?)`, falls back to "unset
container LD_LIBRARY_PATH and hoping for the best", and the compositor
dies before main(). This is why the log is empty.

**Why the service stops:** the most common trigger is launching Steam
with `STEAM_RUNTIME=0` (e.g. a "Steam (stable)" wrapper script). Steam
itself logs `STEAM_RUNTIME is disabled by the user (this is unsupported)`.
Every subsequent auto-restart of the client inherits the setting. Check:

```bash
grep "Launch Service" ~/.local/share/Steam/logs/console-linux.txt | tail -5
# want: "is running pid N" + "bus_name=com.steampowered.PressureVessel.LaunchAlongsideSteam"
# bad:  "starting → exited within 1s → possible problem, disabling"
```

**Fix (verified):**

1. Fully quit Steam (tray → Exit; confirm no `pgrep -f ubuntu12_32/steam` residue).
2. Start Steam with the **normal "Steam" entry** — not `STEAM_RUNTIME=0`.
3. `sudo setcap CAP_SYS_NICE=eip ~/.local/share/Steam/steamapps/common/SteamVR/bin/linux64/vrcompositor-launcher`
4. Verify: the console log shows `is running pid N` (no "exited"/"disabling");
   `busctl --user list | grep LaunchAlongsideSteam` shows the plain name.
5. Start SteamVR → `tail ~/.local/share/Steam/logs/vrcompositor.txt` shows a
   **new banner** → video appears on the Quest.

Upstream: steamVR-for-Linux #936 (same bus-name error + -201; the workaround
repo `ripps818/steamvr-busname-fix` is **not** needed on 32-bit-client
machines that register the plain name normally — the real cause there is
the disabled runtime, not a missing upstream registration).

## Garbled / corrupted video (macro blocking, reset storms)

**Symptom:** the headset shows the Steam desktop but full of macro
blocking; vrlink log shows `Timed out waiting for another accepted video
packet`, `Reset video stream because frame ID was not what we expected`,
`HandleUnrecoverableError(19/20/23/24)` loops, stream resets, `Connection
inactive`. Corrupts over **Wi-Fi too** (rules out the USB path).

**Root cause (local, verified):** a **valid** `DRI_PRIME` in the Steam
client environment (e.g. `1`, or a specific `pci-0000_XX_00_0` = the dGPU) steers the
compositor and the vrlink Vulkan video encoder onto the dGPU. The compositor
**inherits the client's environment** through the launcher service (evidence:
the compositor log itself printed `Invalid value (0) for DRI_PRIME` when the
client ran with `DRI_PRIME=0`). On this RDNA4 hardware the RADV Vulkan video
encode path produces corrupt output. (The independent, separate known Valve
issues are #904 / #965 — same class of symptoms, different trigger.)

**Fix (verified):** start Steam with `DRI_PRIME=0` (invalid → ignored →
SteamVR picks its own GPU → clean video). See `wrappers/steam-igpu.sh`.
Do **not** try to fix this via SteamVR launch options — the compositor is
started by the launcher service and may not receive them; the client's
environment is what counts.

**Discrimination test (if it's not DRI_PRIME):** check the monitor's
mirrored output. Screen garbled too = render layer; only the headset
garbled = encode layer. Also check `streaming_log.txt` / F6 overlay:
"PipeWire NV12 DMABUF + VAAPI HEVC" = hardware encode working; plain
`libx264` = slow CPU fallback (a separate problem, usually 32-bit mesa
too old for the card's VCN).

## App stuck on "connecting…" forever

**Symptom:** discovery succeeds (app finds the PC, local Remote Client
service connects, "usb tethering is available") but no video; the PC's
NCM interface holds a real IPv4 (e.g. 10.86.13.33/29).

**Root cause:** the NCM transport path is **pure IPv6 link-local**
(video UDP 10400, control UDP 39803, discovery mDNS 5353). When the PC's
NCM interface has a real IPv4, the Steam client only announces over IPv4;
the app never gets a v6 path, so the transport never builds. The PC's
default route / internet is irrelevant to the transport.

**Fix:** keep the PC NCM interface v6-only (no IPv4). The Steam Link app
configures the headset side itself (`10.86.13.37/29` static on `usb0`, no
gateway, no default route) — do not add addresses on the headset side
(the shell lacks NET_ADMIN anyway; Android's per-network routing tables
have no default route, so the app's own internet over the cable is
capped, but streaming does not need it).

## PC loses internet when the Quest is plugged in

**Root cause:** NetworkManager auto-activates a profile on the new `enx*`
interface; that profile has no never-default, so NM takes the default
route. (Common when an old NM profile was bound to a stale NCM MAC — the
MAC changes on every Quest boot, so the GUI's toggle ends up activating
the auto profile instead.)

**Fix (verified, permanent):** the three-piece set in `config/`
(`unmanaged-devices=interface-name:enx*` + udev bring-up + `ncm-up`
3 s self-heal). After this, no profile fights survive, and the app
re-toggling USB or the headset rebooting never breaks the PC network.
Delete any old NCM NM profiles (they are bound to dead MACs).

## No video but audio works, Docker on the machine

**Symptom:** audio reaches the headset; video never does; vrserver log
shows `SVLDataLinkUber … list is full` (repeated), NCM never "ADD OK".

**Root cause:** vrlink enumerates every local interface into the
`SVLDataLinkUber` table (hard cap ~16–19, **no dedup**). Many Docker
networks (v4+v6 each take a slot) fill the table before NCM — which is
listed last — ever gets in.

**Fix (verified):** `91-docker-no-v6.rules` (veth/br-* → v4-only) + one
cleanup pass over existing interfaces (in `ncm-install.sh`) + `steam-vr-restart.sh`
to clear the table. The table then fits (e.g. 11 entries < cap) and NCM
registers (log: "ADD OK", zero "could not be added"). Note: empty Docker
networks removed by `docker network rm` **regenerate when compose runs
again** — the udev rule keeps new ones v4-only, so it self-maintains.
The upstream fix is Valve's (dedup in the table).

## Error 616 / "not connected to the wifi" — even with Wi-Fi off

**Not a transport error.** 616 is the app's Wi-Fi *status* check. The
current beta hard-depends on Wi-Fi for the video channel, and discovery
is Wi-Fi-first (a known rough edge). Options, in order of certainty:

- **A. Stream with Wi-Fi on** (measured ~21 MB/s over home Wi-Fi; NCM stays
  registered as backup) — the reliable path for now.
- **D. ALVR** for a deterministic pure-USB path (no Wi-Fi dependency at all;
  mature, open source, first-class on Linux).
- **C. Wait for Valve** (the beta is under active development; no stable
  timeline).

Opting the Steam client into beta helps USB-only *pairing* (first
discovery) but does **not** fix Wi-Fi-off streaming — the pairing is done;
you are stuck on the app's Wi-Fi check, not discovery.

## Non-VR (Steam Link app game mode) capped at low FPS

See the "Non-VR low FPS on Wayland" section of the README. In short:
Wayland session + client without `-pipewire` → desktop capture
unavailable → rate-limited X11/Xwayland grab fallback. The Quest's 120 Hz
setting does nothing here — it is display refresh; the stream source is
the low-FPS grab. VR is unaffected because the SteamVR compositor
produces its own frames (no desktop capture needed).

## NCM dead ends (verified, don't re-tread)

- `adb shell svc usb setFunctions ncm,adb` — never works; the framework
  requires exactly one function bit. Use `ncm` alone; `adb` is OR'd in
  automatically while USB debugging is on.
- `rndis,adb` — RNDIS does not exist on this hardware; the gadget HAL
  rejects it (status 4) and the device falls back to charge-only.
- `Tethering: ERROR could not enable IpServer for function NCM` in logcat
  is a red herring: the build's `tetherableNcmRegexs` is empty, so Android
  tethering can never attach to NCM. The working path is the Ethernet
  service, not tethering.
- Any active `VpnService` on the headset silently swallows the connection
  (captures all traffic regardless of routing; every status check reports
  success). If the app can't find the PC, kill the VPN first.
- ADB cannot be removed: `setCurrentFunctions` is a `@SystemApi` behind the
  signature/privileged `MANAGE_USB` permission, and there is no host-side
  trigger (single USB configuration; AOA accessory gives bulk endpoints,
  not a network interface). The NCM mode also does not persist across
  unplug/reboot (needs root to force `persist.sys.usb.config`), so
  per-session re-setup is inherent.

## Compositor not coming back after a SteamVR restart

If `vrcompositor` is dead and restarthelper did not relaunch it, the most
likely causes in order: the launcher-service problem above (check
`console-linux.txt`), the DRI_PRIME problem (garbled rather than dead, but
check), or simply needing to launch SteamVR from the Steam client once.
After any SteamVR update, redo the `setcap` on `vrcompositor-launcher`.
