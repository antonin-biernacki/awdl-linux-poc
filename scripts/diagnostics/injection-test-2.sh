#!/usr/bin/env bash
# Monitor-mode reception and injection test for wlp2s0.
# Wi-Fi is always restored on exit, even on error or Ctrl+C.
set -u

IFACE=wlp2s0
OUT="${SUDO_USER:+/home/$SUDO_USER}/injection-test-2.txt"
OUT="${OUT:-$HOME/injection-test-2.txt}"

restore() {
    ip link set "$IFACE" down
    iw dev "$IFACE" set type managed
    ip link set "$IFACE" up
    nmcli device set "$IFACE" managed yes
    echo "Wi-Fi restored."
}
trap restore EXIT

nmcli device set "$IFACE" managed no
ip link set "$IFACE" down
iw dev "$IFACE" set type monitor
ip link set "$IFACE" up

{
    for chan in 6 157; do
        iw dev "$IFACE" set channel "$chan"
        echo "=== Channel $chan: reception (frames captured in 5 s) ==="
        timeout 5 tcpdump -i "$IFACE" -nn -q 2>/dev/null | wc -l
        echo "=== Channel $chan: injection test ==="
        aireplay-ng --test "$IFACE"
    done
} 2>&1 | tee "$OUT"
