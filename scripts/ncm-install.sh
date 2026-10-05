#!/bin/sh
# One-time install of the Quest NCM / Steam Link over USB plumbing.
# Run once per machine: sudo ./scripts/ncm-install.sh
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)

# 1. NetworkManager: never manage enx* (NCM) interfaces.
install -m 0644 "$HERE/config/90-ncm-unmanaged.conf" /etc/NetworkManager/conf.d/90-ncm-unmanaged.conf

# 2. udev: bring new NCM interfaces up on plug.
install -m 0644 "$HERE/config/90-ncm-up.rules" /etc/udev/rules.d/90-ncm-up.rules

# 3. udev (Docker users): keep veth/br-* v4-only so they stop filling the
#    SVLDataLinkUber table. Harmless on non-Docker machines.
install -m 0644 "$HERE/config/91-docker-no-v6.rules" /etc/udev/rules.d/91-docker-no-v6.rules

# 4. systemd: 3s self-heal for the NCM interface.
install -m 0644 "$HERE/config/ncm-up.service" /etc/systemd/system/ncm-up.service
systemctl daemon-reload
systemctl enable --now ncm-up.service

# 5. One-time cleanup: disable IPv6 on EXISTING veth/br-* interfaces
#    (the udev rule only covers new ones).
for dev in /sys/class/net/*; do
    name=$(basename "$dev")
    case "$name" in
        veth*|br-*)
            if [ -e "$dev/ipv6" ]; then
                sysctl -w "net.ipv6.conf.$name.disable_ipv6=1" >/dev/null 2>&1 || true
            fi
            ;;
    esac
done

# 6. Bring the NCM interface up right now, if the Quest is already plugged in.
for dev in /sys/class/net/*; do
    drv=$(readlink "$dev/device/driver" 2>/dev/null || true)
    case "$drv" in
        *cdc_ncm*)
            name=$(basename "$dev")
            ip link set "$name" up 2>/dev/null || true
            echo "NCM interface up: $name"
            ;;
    esac
done

echo "Done. Verify with: sudo $HERE/scripts/ncm-verify.sh"
