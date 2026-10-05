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
# The "Steam (iGPU)" desktop entry should point at this script.
# The name is misleading: this is the VR-required config, not an
# iGPU-only one.
export DRI_PRIME=0
exec /usr/bin/steam -cef-disable-gpu -pipewire "$@"
