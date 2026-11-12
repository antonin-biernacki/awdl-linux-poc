#!/usr/bin/env bash
# Check whether rtw89 really tunes to the requested channel in monitor mode.
# For each channel: requested channel, channel reported by iw, frame count and
# the radio frequencies seen in the radiotap headers of captured frames.
# Usage: channel-test.sh [CHANNEL...]
# Wi-Fi is always restored on exit.
set -u

IFACE=wlp2s0
DURATION=5
OUT=/home/abiernacki/channel-test.txt
PCAP_DIR=$(mktemp -d)

restore() {
    rm -rf "$PCAP_DIR"
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

capture() {
    local label=$1 pcap="$PCAP_DIR/$1.pcap"
    echo "=== $label ==="
    echo "iw reports: $(iw dev "$IFACE" info | grep -o 'channel [0-9]* ([0-9]* MHz)' || echo none)"
    timeout "$DURATION" tcpdump -i "$IFACE" -w "$pcap" 2>/dev/null
    echo "frames: $(tcpdump -r "$pcap" -nn 2>/dev/null | wc -l)"
    echo "frequencies seen:"
    tcpdump -r "$pcap" -nn 2>/dev/null | grep -o '[0-9]\{4\} MHz' | sort | uniq -c | sort -rn | head -3
}

CHANNELS=("${@:-157 6 11 149 157}")
# shellcheck disable=SC2206
CHANNELS=(${CHANNELS[*]})

{
    for chan in "${CHANNELS[@]}"; do
        iw dev "$IFACE" set channel "$chan"
        capture "ch$chan"
    done
} 2>&1 | tee "$OUT"
