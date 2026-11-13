#!/usr/bin/env bash
# rtw89 in monitor mode only receives on the channel the firmware last operated
# on. For each AWDL channel: start a short-lived hotspot on it, switch to
# monitor mode on the same channel and capture (iPhone share sheet open on
# AirDrop). Captures are kept in ~/awdl-captures/ for inspection.
# Usage: hotspot-trick.sh [CHANNEL...]   (default: 149 44 6)
# Wi-Fi is always restored and the hotspot profile removed.
set -u

IFACE=wlp2s0
DURATION=15
HOTSPOT_NAME=poc-test
OUT=/home/abiernacki/hotspot-trick.txt
CAPTURE_DIR=/home/abiernacki/awdl-captures
AWDL_FILTER='type mgt subtype action and wlan[24] == 0x7f and wlan[25] == 0x00 and wlan[26] == 0x17 and wlan[27] == 0xf2'
CHANNELS=("${@:-149 44 6}")
# shellcheck disable=SC2206
CHANNELS=(${CHANNELS[*]})

restore() {
    nmcli connection delete "$HOTSPOT_NAME" >/dev/null 2>&1
    ip link set "$IFACE" down
    iw dev "$IFACE" set type managed
    ip link set "$IFACE" up
    nmcli device set "$IFACE" managed yes
    chown -R "${SUDO_USER:-root}": "$CAPTURE_DIR" "$OUT" 2>/dev/null
    echo "Wi-Fi restored."
}
trap restore EXIT

iw_channel() {
    iw dev "$IFACE" info | grep -o 'channel [0-9]* ([0-9]* MHz)' || echo none
}

probe_channel() {
    local chan=$1 band pcap="$CAPTURE_DIR/ch$1.pcap"
    if [ "$chan" -le 14 ]; then band=bg; else band=a; fi

    echo "=== Channel $chan: hotspot ==="
    ip link set "$IFACE" down
    iw dev "$IFACE" set type managed
    ip link set "$IFACE" up
    nmcli device set "$IFACE" managed yes
    sleep 2
    nmcli device wifi hotspot ifname "$IFACE" con-name "$HOTSPOT_NAME" \
        ssid "$HOTSPOT_NAME" band "$band" channel "$chan" password "poc-test-pw" >/dev/null
    sleep 5
    echo "iw reports: $(iw_channel)"
    nmcli connection down "$HOTSPOT_NAME" >/dev/null

    echo "=== Channel $chan: monitor mode ==="
    nmcli device set "$IFACE" managed no
    ip link set "$IFACE" down
    iw dev "$IFACE" set type monitor
    ip link set "$IFACE" up
    iw dev "$IFACE" set channel "$chan"
    echo "iw reports: $(iw_channel)"

    timeout "$DURATION" tcpdump -i "$IFACE" -w "$pcap" 2>/dev/null
    echo "all frames:  $(tcpdump -r "$pcap" -nn 2>/dev/null | wc -l)"
    echo "AWDL frames: $(tcpdump -r "$pcap" -nn "$AWDL_FILTER" 2>/dev/null | wc -l)"
    echo "frequencies seen:"
    tcpdump -r "$pcap" -nn 2>/dev/null | grep -o '[0-9]\{4\} MHz' | sort | uniq -c | sort -rn | head -3
}

mkdir -p "$CAPTURE_DIR"
{
    for chan in "${CHANNELS[@]}"; do
        probe_channel "$chan"
    done
} 2>&1 | tee "$OUT"
