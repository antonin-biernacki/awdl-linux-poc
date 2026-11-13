#!/usr/bin/env bash
# Summarize a run of airdrop-poc.sh from its directory in out/runs/.
# Run it after `sudo CAPTURE=1 bash scripts/airdrop-poc.sh ...`, without sudo.
#
# Usage: bash scripts/diagnostics/summarize-run.sh [RUN_DIR]   (default: out/latest)
# Needs tshark (package wireshark-cli) for the capture sections.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUT_DIR="$REPO/out"
RUN_DIR=${1:-$OUT_DIR/latest}
OWL_LOG="$RUN_DIR/owl.log"
OPENDROP_LOG="$RUN_DIR/opendrop.log"
WLAN_PCAP="$RUN_DIR/wlan.pcap"
AWDL_PCAP="$RUN_DIR/awdl0.pcap"

section() {
    printf '\n== %s\n' "$1"
}

[ -f "$OWL_LOG" ] || { echo "error: no $OWL_LOG, run airdrop-poc.sh first" >&2; exit 1; }
SELF_MAC=$(grep -o -m1 'addr [0-9a-f:]\{17\}' "$OWL_LOG" | cut -d' ' -f2)
# OpenDrop moves to the next port when 8771 is taken: use the announced one.
PORT=$(grep -o -m1 'port [0-9]*' "$OPENDROP_LOG" 2>/dev/null | cut -d' ' -f2)
PORT=${PORT:-8771}
echo "run: $(cd "$RUN_DIR" && pwd -P)"

section "OWL: peers and elections"
grep -E 'add peer|remove peer' "$OWL_LOG" | sed 's/ INFO : / /'
echo "election changes: $(grep -c 'new election tree' "$OWL_LOG")"

if command -v tshark >/dev/null && [ -f "$WLAN_PCAP" ]; then
    section "Wi-Fi frames per AWDL peer (wlan.pcap)"
    duration=$(tshark -r "$WLAN_PCAP" -T fields -e frame.time_relative 2>/dev/null | tail -1)
    echo "capture length: ${duration%.*} s"
    printf '%-18s %8s %8s %10s %12s\n' "peer" "action" "data" "action/s" "median rssi"
    peers=$(grep -o 'add peer [0-9a-f:]\{17\}' "$OWL_LOG" | cut -d' ' -f3 | sort -u)
    for peer in $peers; do
        tshark -r "$WLAN_PCAP" -Y "wlan.ta == $peer" \
            -T fields -e wlan.fc.type -e radiotap.dbm_antsignal 2>/dev/null |
            awk -v peer="$peer" -v duration="${duration:-1}" '
                { if ($1 == 0) action++; else if ($1 == 2) data++
                  split($2, rssi, ","); values[n++] = rssi[1] }
                END {
                    asort(values)
                    median = n ? values[int((n + 1) / 2)] : "-"
                    printf "%-18s %8d %8d %10.1f %12s\n", peer, action, data,
                        action / (duration > 0 ? duration : 1), median
                }'
    done
fi

if command -v tshark >/dev/null && [ -f "$AWDL_PCAP" ]; then
    section "IPv6 traffic on awdl0 (awdl0.pcap)"
    self_ip=$(tshark -r "$AWDL_PCAP" -T fields -e ipv6.src 2>/dev/null |
        grep -m1 -i "$(echo "$SELF_MAC" | cut -d: -f4- | tr -d :)" ||
        tshark -r "$AWDL_PCAP" -T fields -e ipv6.src 2>/dev/null | head -1)
    echo "this PC: $self_ip"
    echo "packets received, per source:"
    tshark -r "$AWDL_PCAP" -Y "ipv6.src != $self_ip" -T fields -e ipv6.src 2>/dev/null |
        sort | uniq -c | sed 's/^/  /'
    echo "mDNS queries for _airdrop._tcp from peers:" \
        "$(tshark -r "$AWDL_PCAP" -Y "ipv6.src != $self_ip && dns.qry.name contains \"_airdrop\"" 2>/dev/null | wc -l)"
    echo "TCP connections to the AirDrop server (announced port $PORT):" \
        "$(tshark -r "$AWDL_PCAP" -Y "tcp.dstport == $PORT && tcp.flags.syn == 1 && tcp.flags.ack == 0" \
            -T fields -e tcp.stream 2>/dev/null | sort -u | wc -l)"
    echo "TCP connections to other ports:" \
        "$(tshark -r "$AWDL_PCAP" -Y "tcp.dstport != $PORT && tcp.flags.syn == 1 && tcp.flags.ack == 0 && ipv6.src != $self_ip" \
            -T fields -e tcp.dstport 2>/dev/null | sort | uniq -c | tr '\n' ' ')"
    # Highest byte of our data the peer acknowledged, per connection: stuck at 1
    # means none of our segments (e.g. the TLS ServerHello) reached it.
    echo "bytes acknowledged by the peer, per connection:"
    tshark -r "$AWDL_PCAP" -Y "tcp.dstport == $PORT" \
        -T fields -e tcp.stream -e tcp.ack 2>/dev/null |
        awk '{ if ($2 > max[$1] + 0) max[$1] = $2 }
             END { for (s in max) printf "  #%s: %d\n", s, (max[s] > 1 ? max[s] - 1 : 0) }' |
        sort -t'#' -k2 -n
fi

if [ -f "$OPENDROP_LOG" ]; then
    section "OpenDrop (opendrop.log)"
    grep -E 'Announcing|Receiving|Exception|Error|POST|Ask|Upload|Discover' "$OPENDROP_LOG" ||
        echo "nothing notable"
fi

section "Received files (out/received)"
find "$OUT_DIR/received" -type f -printf '%s bytes  %p\n' 2>/dev/null | grep . || echo "none"
