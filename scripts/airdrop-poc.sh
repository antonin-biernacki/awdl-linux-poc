#!/usr/bin/env bash
# Proof of concept: real AirDrop between this PC and an Apple device.
#
# Chain: short-lived hotspot on the AWDL channel (rtw89 quirk) -> plain monitor
# mode -> OWL in the background (creates awdl0) -> OpenDrop on awdl0.
#
# Usage (from the repository root):
#   sudo bash scripts/airdrop-poc.sh find            # list nearby AirDrop devices
#   sudo bash scripts/airdrop-poc.sh receive         # be visible, accept files
#   sudo bash scripts/airdrop-poc.sh send FILE       # discover for 30 s, send to device 0
#
# The Apple device must have AirDrop set to "Everyone".
# Stop with Ctrl+C: Wi-Fi is always restored and the hotspot profile removed.
# Each run keeps its logs in out/runs/<date>-<mode>/ (git-ignored), out/latest
# points to the last one. Received files land in out/received/.
# Set CAPTURE=1 to also record the traffic of awdl0 (out/awdl0.pcap) and the
# raw Wi-Fi frames of the monitor interface (out/wlan.pcap).
# Extra OWL options go in OWL_ARGS, e.g. OWL_ARGS="-f -vv" (no RSSI filter, trace),
# extra OpenDrop options in OPENDROP_ARGS, e.g. OPENDROP_ARGS="-d" (debug).
# Summarize a run with: bash scripts/diagnostics/summarize-run.sh
# Set TCP_MSS (bytes) to cap the TCP segments sent to the Apple device
# (default 0: no cap). Tested with 500: it did not help with this card.
set -u

IFACE=${IFACE:-wlp2s0}
CHANNEL=${CHANNEL:-149}
DEVICE_NAME=${DEVICE_NAME:-poc}
FIND_SECONDS=${FIND_SECONDS:-30}
CAPTURE=${CAPTURE:-0}
OWL_ARGS=${OWL_ARGS:-}
OPENDROP_ARGS=${OPENDROP_ARGS:-}
TCP_MSS=${TCP_MSS:-0}
NFT_TABLE=airdrop_poc
HOTSPOT_NAME=poc-hotspot

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR="$REPO/out"
OPENDROP="$REPO/.venv/bin/opendrop"
RUN_DIR=

usage() {
    sed -n '7,10p' "${BASH_SOURCE[0]}" | sed 's/^# //'
    exit 2
}

die() {
    echo "error: $*" >&2
    exit 1
}

MODE=${1:-}
case "$MODE" in
    find | receive) ;;
    send) [ -f "${2:-}" ] || die "send needs an existing FILE" ;;
    *) usage ;;
esac

[ "$(id -u)" -eq 0 ] || die "run with sudo"
[ -n "${SUDO_USER:-}" ] || die "run with sudo from your user account (SUDO_USER is empty)"
USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
OWL_BIN=${OWL_BIN:-$USER_HOME/.local/src/owl/build/daemon/owl}
[ -x "$OWL_BIN" ] || die "OWL not found at $OWL_BIN"
[ -x "$OPENDROP" ] || die "OpenDrop not found at $OPENDROP (run scripts/setup-opendrop.sh first)"

RUN_DIR="$OUT_DIR/runs/$(date +%Y%m%d-%H%M%S)-$MODE"
OWL_LOG="$RUN_DIR/owl.log"
OPENDROP_LOG="$RUN_DIR/opendrop.log"
AWDL_PCAP="$RUN_DIR/awdl0.pcap"
WLAN_PCAP="$RUN_DIR/wlan.pcap"
mkdir -p "$OUT_DIR/received" "$RUN_DIR"
ln -sfn "runs/$(basename "$RUN_DIR")" "$OUT_DIR/latest"
: >"$OPENDROP_LOG"
# OpenDrop runs as the user and writes received files here.
chown -R "$SUDO_USER": "$OUT_DIR"
OWL_PID=
CAPTURE_PIDS=()

stop_process() {
    [ -n "$1" ] && kill "$1" 2>/dev/null && wait "$1" 2>/dev/null
}

# On Ctrl+C the pipeline ends before OpenDrop has finished shutting down; a
# leftover instance keeps port 8771 and the next run silently moves to 8772.
stop_opendrop() {
    pkill -INT -f "^[^ ]*python[^ ]* $OPENDROP " 2>/dev/null || return 0
    for _ in $(seq 10); do
        pgrep -f "^[^ ]*python[^ ]* $OPENDROP " >/dev/null || return 0
        sleep 0.5
    done
    pkill -KILL -f "^[^ ]*python[^ ]* $OPENDROP "
}

restore() {
    stop_opendrop
    nft delete table inet "$NFT_TABLE" 2>/dev/null
    for pid in "${CAPTURE_PIDS[@]}"; do
        stop_process "$pid"
    done
    stop_process "$OWL_PID"
    nmcli connection delete "$HOTSPOT_NAME" >/dev/null 2>&1
    ip link set "$IFACE" down
    iw dev "$IFACE" set type managed
    ip link set "$IFACE" up
    nmcli device set "$IFACE" managed yes
    chown -R "$SUDO_USER": "$OUT_DIR"
    echo "Wi-Fi restored. Logs in $RUN_DIR"
}
trap restore EXIT

as_user() {
    sudo -u "$SUDO_USER" -H "$@"
}

# Runs OpenDrop on awdl0 as the user, output also appended to OPENDROP_LOG.
# Set OPENDROP_TIMEOUT (seconds) to stop it with SIGINT after that delay.
# Known harmless warnings are hidden.
opendrop() {
    local timeout_cmd=()
    [ -n "${OPENDROP_TIMEOUT:-}" ] && timeout_cmd=(timeout -s INT "$OPENDROP_TIMEOUT")
    # shellcheck disable=SC2086 # OPENDROP_ARGS is a list of options
    as_user env PYTHONWARNINGS=ignore::FutureWarning PYTHONUNBUFFERED=1 "${timeout_cmd[@]}" \
        "$OPENDROP" "$@" -i awdl0 $OPENDROP_ARGS 2>&1 |
        grep --line-buffered -v -e pkg_resources -e 'from pkg_resources' | tee -a "$OPENDROP_LOG"
}

# True once awdl0 has a link-local IPv6 address that sockets can bind to,
# i.e. duplicate address detection (DAD) is over.
awdl0_address_ready() {
    ip -6 addr show dev awdl0 scope link -tentative 2>/dev/null | grep -q inet6
}

awdl0_dad_failed() {
    ip -6 addr show dev awdl0 dadfailed 2>/dev/null | grep -q inet6
}

echo "== Hotspot on channel $CHANNEL (so the firmware operates on it)"
nmcli device wifi hotspot ifname "$IFACE" con-name "$HOTSPOT_NAME" \
    ssid "$HOTSPOT_NAME" band a channel "$CHANNEL" password "poc-hotspot" >/dev/null ||
    die "hotspot failed"
sleep 5
nmcli connection down "$HOTSPOT_NAME" >/dev/null

echo "== Monitor mode on channel $CHANNEL"
nmcli device set "$IFACE" managed no
ip link set "$IFACE" down
iw dev "$IFACE" set type monitor
ip link set "$IFACE" up
iw dev "$IFACE" set channel "$CHANNEL"

# Make the Apple device believe our MSS is TCP_MSS: the kernel then never sends
# it TCP segments larger than that (rewrites the MSS option of incoming SYNs).
if [ "$TCP_MSS" -gt 0 ]; then
    echo "== Capping TCP segments on awdl0 to $TCP_MSS bytes"
    nft delete table inet "$NFT_TABLE" 2>/dev/null # left over by a killed run
    nft -f - <<EOF_NFT || die "nftables rule failed"
table inet $NFT_TABLE {
    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname "awdl0" tcp flags & (syn | ack) == syn tcp option maxseg size set $TCP_MSS
    }
}
EOF_NFT
fi

echo "== Starting OWL (log: $OWL_LOG)"
# shellcheck disable=SC2086 # OWL_ARGS is a list of options
"$OWL_BIN" -i "$IFACE" -c "$CHANNEL" -N -v $OWL_ARGS >"$OWL_LOG" 2>&1 &
OWL_PID=$!

# Show AWDL peers as OWL finds or loses them, so the user knows when the Apple
# device is in sync. tail stops by itself when OWL exits.
tail -n +1 -F --pid="$OWL_PID" "$OWL_LOG" 2>/dev/null |
    grep --line-buffered -E 'add peer|remove peer' |
    sed -u 's/^[0-9:]* INFO : /   [owl] /' &

for _ in $(seq 20); do
    awdl0_address_ready && break
    awdl0_dad_failed && die "duplicate address detection failed on awdl0: $(ip -6 addr show dev awdl0)"
    kill -0 "$OWL_PID" 2>/dev/null || die "OWL exited, see $OWL_LOG"
    sleep 1
done
awdl0_address_ready || die "awdl0 has no usable IPv6 address: $(ip -6 addr show dev awdl0 2>&1)"
echo "awdl0 up: $(ip -6 -br addr show dev awdl0)"

if [ "$CAPTURE" = 1 ]; then
    tcpdump -i awdl0 -w "$AWDL_PCAP" 2>/dev/null &
    CAPTURE_PIDS+=($!)
    tcpdump -i "$IFACE" -w "$WLAN_PCAP" 2>/dev/null &
    CAPTURE_PIDS+=($!)
    echo "== Capturing to $AWDL_PCAP and $WLAN_PCAP"
fi

case "$MODE" in
    find)
        echo "== Looking for devices (Ctrl+C to stop)"
        opendrop find
        ;;
    receive)
        echo "== Visible as \"$DEVICE_NAME\" (Ctrl+C to stop)"
        cd "$OUT_DIR/received" && opendrop receive -n "$DEVICE_NAME"
        ;;
    send)
        file=$(realpath "$2")
        echo "== Looking for devices for $FIND_SECONDS s"
        OPENDROP_TIMEOUT=$FIND_SECONDS opendrop find
        echo "== Sending $file to device 0"
        opendrop send -r 0 -f "$file"
        ;;
esac

echo "== OWL peers seen: $(grep -c 'add peer' "$OWL_LOG")"
