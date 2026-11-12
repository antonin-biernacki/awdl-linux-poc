#!/usr/bin/env bash
# Passive scan: count all frames, beacons and AWDL action frames (Apple OUI 00:17:f2) on each AWDL
# social channel. Keep the iPhone share sheet open on AirDrop while it runs.
# Wi-Fi is always restored on exit.
set -u

IFACE=wlp2s0
DURATION=10
OUT=/home/abiernacki/awdl-scan.txt

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

AWDL_FILTER='type mgt subtype action and wlan[24] == 0x7f and wlan[25] == 0x00 and wlan[26] == 0x17 and wlan[27] == 0xf2'
PCAP_DIR=$(mktemp -d)

{
    for chan in 6 44 149 157; do
        iw dev "$IFACE" set channel "$chan"
        pcap="$PCAP_DIR/ch$chan.pcap"
        echo "=== Channel $chan (${DURATION} s) ==="
        timeout "$DURATION" tcpdump -i "$IFACE" -w "$pcap" 2>/dev/null
        echo "all frames:    $(tcpdump -r "$pcap" -nn 2>/dev/null | wc -l)"
        echo "beacons:       $(tcpdump -r "$pcap" -nn 'type mgt subtype beacon' 2>/dev/null | wc -l)"
        echo "action frames: $(tcpdump -r "$pcap" -nn 'type mgt subtype action' 2>/dev/null | wc -l)"
        echo "AWDL frames:   $(tcpdump -r "$pcap" -nn "$AWDL_FILTER" 2>/dev/null | wc -l)"
        echo "AWDL senders:"
        tcpdump -r "$pcap" -e -nn "$AWDL_FILTER" 2>/dev/null \
            | grep -o -i 'SA:[0-9a-f:]\{17\}' | sort | uniq -c | sort -rn | head -5
    done
} 2>&1 | tee "$OUT"
rm -rf "$PCAP_DIR"
