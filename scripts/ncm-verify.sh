#!/bin/sh
# Verify the NCM / Steam Link over USB chain.
# Usage: sudo ./scripts/ncm-verify.sh
set -u

ok=0; fail=0
pass() { echo "  PASS  $1"; ok=$((ok+1)); }
failc() { echo "  FAIL  $1"; fail=$((fail+1)); }

echo "== NCM interface =="
found=0
for dev in /sys/class/net/*; do
    drv=$(readlink "$dev/device/driver" 2>/dev/null || true)
    case "$drv" in
        *cdc_ncm*)
            found=1
            name=$(basename "$dev")
            pass "found NCM interface: $name"
            if ip -o link show "$name" 2>/dev/null | grep -q "state UP"; then
                pass "$name is UP"
            else
                failc "$name is DOWN (ncm-up.service should fix within ~3s)"
            fi
            # Transport is pure v6 link-local. The interface must NOT hold a
            # real IPv4 (a v4 address makes the Steam client v4-only-announce
            # and the v6 transport never builds).
            if ip -4 -o addr show "$name" 2>/dev/null | grep -q "inet "; then
                failc "$name holds an IPv4 — remove it (ip addr flush dev $name)"
            else
                pass "$name has no IPv4 (required)"
            fi
            if ip -6 -o addr show "$name" 2>/dev/null | grep -q "inet6 fe80"; then
                pass "$name has IPv6 link-local"
            else
                failc "$name missing IPv6 link-local"
            fi
            ;;
    esac
done
[ "$found" = 1 ] || failc "no cdc_ncm interface — plug the Quest in (USB debugging on)"

echo
echo "== Self-heal service =="
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet ncm-up.service; then
        pass "ncm-up.service active"
    else
        failc "ncm-up.service not active (systemctl enable --now ncm-up.service)"
    fi
    if systemctl is-enabled --quiet ncm-up.service; then
        pass "ncm-up.service enabled at boot"
    else
        failc "ncm-up.service not enabled at boot"
    fi
fi

echo
echo "== Result: $ok passed, $fail failed =="
[ "$fail" = 0 ]
