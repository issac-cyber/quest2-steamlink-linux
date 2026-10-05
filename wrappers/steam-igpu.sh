#!/bin/sh
# Steam launch wrapper for VR + Steam Link streaming.
#
#   DRI_PRIME=0
#     Invalid on purpose. A VALID DRI_PRIME (e.g. 1, or a specific
#     pci-0000_XX_00_0 pointing at the dGPU) steers the compositor + vrlink Vulkan
#     video encoder onto the dGPU, whose RADV Vulkan video encode path
#     produces corrupt output (garbled video) on this hardware. With an
#     invalid value SteamVR picks its own GPU and video is clean.
#     Steam logs "Invalid value (0) for DRI_PRIME. Should be > 0" — that
#     warning is the sign this is doing its job.
#
#   (STEAM_RUNTIME stays enabled)
#     DO NOT set STEAM_RUNTIME=0 here. Disabling the runtime prevents
#     steam-runtime-launcher-service from starting, which kills the
#     compositor at launch (zero log, ~21 s watchdog abort, error 450/-201).
#
#   -cef-disable-gpu
#     Keeps the CEF UI renderer off the GPU (input-crash avoidance on
#     headless dGPU setups). UI only; does not affect capture or VR.
#
#   -pipewire
#     Enables PipeWire screen capture on Wayland sessions. Without it,
#     non-VR (Steam Link app game mode) streaming falls back to a
#     rate-limited X11/Xwayland grab. Caveats: multi-GPU crash risk
#     (steamVR-for-Linux #915) — re-test the VR path after adding it;
#     32-bit client needs 32-bit libEGL/libva (check streaming_log.txt).
#
#   STEAM_FORCE_CLIENT=steamrt64
#     Forces the 64-bit client (SteamRT3, publicbeta opt-in). Fixes the
#     32-bit encoding wall: the 32-bit client's mesa (23.0) predates RDNA4
#     VCN 5.0, so VAAPI hw encode falls back to libx264 (slow CPU path);
#     the 64-bit client's mesa (26.x) has the hw encoder. `:-` default so a
#     terminal override (e.g. ubuntu12_32) still wins.
#
#   VALVE_SKIP_RUNTIME_SAFETY=1
#     Required with the 64-bit client: vrcompositor-launcher.sh otherwise
#     re-execs itself in a loop (LegacySteamRuntime missing, the legacy
#     scout path is a no-op stub) until "Argument list too long", and the
#     compositor never launches. With this set, the compositor runs in the
#     64-bit environment and comes up — but SLOWLY (a few minutes).
#     Do not kill it early.
#
# The "Steam (64-bit + VR)" desktop entry should point at this script.
# The name is misleading: this is the VR-required config, not an
# iGPU-only one.
#
# IMPORTANT (GNOME): do NOT rely on .desktop Environment= lines — GNOME
# does not apply them (verified via /proc/<client>/environ) and gnome-shell
# caches stale entries. Export the variables HERE, in the script.
#
# Also required (64-bit client, separate issue steamVR-for-Linux #936):
# the plain D-Bus name com.steampowered.PressureVessel.LaunchAlongsideSteam
# is not registered (only the .Instance<N> suffix is). Run
# ripps818/steamvr-busname-fix (a small systemd user service that
# re-registers the plain name every 5 s and after every Steam restart).
# It is a stopgap: uninstall it once Valve fixes #936.
export DRI_PRIME=0
export STEAM_FORCE_CLIENT="${STEAM_FORCE_CLIENT:-steamrt64}"
export VALVE_SKIP_RUNTIME_SAFETY=1
exec /usr/bin/steam -cef-disable-gpu -pipewire "$@"
