#!/usr/bin/env bash
# Check whether a second Wi-Fi adapter (e.g. MT7612U USB key) needs the rtw89
# workarounds: no hotspot trick here, just active monitor mode.
# mac80211 only tunes an active monitor interface through its virtual monitor,
# which exists only if a plain monitor interface (HELPER) opens first.
# For each AWDL channel: channel reported by iw, frames captured, radio
# frequencies seen in radiotap headers, AWDL frames (AWDL BSSID 00:25:00:ff:94:73) and
# injection test. Keep the iPhone share sheet open on AirDrop while it runs.
# Only IFACE is touched: the built-in Wi-Fi stays connected.
# Usage (from the repository root):
#   sudo IFACE=wlp4s0f4u1 bash scripts/diagnostics/adapter-test.sh [CHANNEL...]
# Output: out/adapter-test.txt. IFACE is restored on exit.
set -u

IFACE=${IFACE:-}
DURATION=${DURATION:-10}
[ -n "$IFACE" ] || { echo "error: set IFACE (see: iw dev)" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "error: run with sudo" >&2; exit 1; }

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUT="$REPO/out/adapter-test.txt"
mkdir -p "$REPO/out"
PCAP_DIR=$(mktemp -d)
HELPER=pocmon0
PHY=phy$(iw dev "$IFACE" info | awk '/wiphy/ {print $2}')

restore() {
    rm -rf "$PCAP_DIR"
    iw dev "$HELPER" del 2>/dev/null
    ip link set "$IFACE" down
    iw dev "$IFACE" set type managed
    ip link set "$IFACE" up
    nmcli device set "$IFACE" managed yes
    [ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER": "$REPO/out"
    echo "$IFACE restored. Output in $OUT"
}
trap restore EXIT

nmcli device set "$IFACE" managed no
ip link set "$IFACE" down
iw dev "$HELPER" del 2>/dev/null
iw phy "$PHY" interface add "$HELPER" type monitor
ip link set "$HELPER" up
iw dev "$IFACE" set type monitor
iw dev "$IFACE" set monitor active otherbss control
ip link set "$IFACE" up

# AWDL BSSID, as OWL filters. Type or byte filters (subtype action, wlan[24])
# fail with the radiotap headers of mt76 (several presence words): no match.
AWDL_FILTER='wlan addr3 00:25:00:ff:94:73'
CHANNELS=("${@:-6 44 149}")
# shellcheck disable=SC2206
CHANNELS=(${CHANNELS[*]})

{
    echo "adapter: $IFACE ($(iw dev "$IFACE" info | grep -o 'wiphy [0-9]*'))"
    echo "monitor flags: $(iw dev "$IFACE" info | grep -i -o 'type monitor.*' || echo unknown)"
    for chan in "${CHANNELS[@]}"; do
        iw dev "$IFACE" set channel "$chan"
        pcap="$PCAP_DIR/ch$chan.pcap"
        echo
        echo "=== Channel $chan (${DURATION} s) ==="
        echo "iw reports:    $(iw dev "$HELPER" info | grep -o 'channel [0-9]* ([0-9]* MHz)' || echo 'none (normal for active monitor)')"
        timeout "$DURATION" tcpdump -i "$IFACE" -w "$pcap" 2>/dev/null
        echo "all frames:    $(tcpdump -r "$pcap" -nn 2>/dev/null | wc -l)"
        echo "AWDL frames:   $(tcpdump -r "$pcap" -nn "$AWDL_FILTER" 2>/dev/null | wc -l)"
        echo "frequencies seen:"
        tcpdump -r "$pcap" -nn 2>/dev/null | grep -o '[0-9]\{4\} MHz' | sort | uniq -c | sort -rn | head -3
        echo "AWDL senders:"
        tcpdump -r "$pcap" -e -nn "$AWDL_FILTER" 2>/dev/null |
            grep -o -i 'SA:[0-9a-f:]\{17\}' | sort | uniq -c | sort -rn | head -5
        echo "--- injection test"
        timeout 40 aireplay-ng --test "$IFACE" 2>&1 | tr '\r' '\n' |
            grep -E '^[0-9]{2}:[0-9]{2}:[0-9]{2} ' # timestamped lines only, no progress
    done
} 2>&1 | tee "$OUT"
