#!/bin/sh
# Restart SteamVR cleanly.
#
# vrserver in "-waitformonitor" mode ignores SIGTERM; SIGKILL is needed.
# The restarthelper relaunches SteamVR automatically (~30-60 s).
#
# The bracket trick (vrserve[r]) prevents this pkill from matching and
# killing its own shell.
#
# When to use:
#  - the SVLDataLinkUber table filled up (Docker v6 interfaces) and NCM
#    never registered — the restart clears the table
#  - after major SteamVR state problems
#
# Note: restarting SteamVR also restarts the compositor (vrcompositor).
# If it does not come back, see docs/troubleshooting.md (the zero-log
# death chain / error 450 / -201).
pkill -9 -f "vrserve[r] -waitformonitor"
echo "vrserver killed. restarthelper relaunches SteamVR in ~30-60 s."
echo "Then check: tail ~/.local/share/Steam/logs/vrcompositor.txt (want a NEW banner)"
