#!/usr/bin/env bash
# Proof of concept: real AirDrop between this PC and an Apple device.
#
# Chain: short-lived hotspot on the AWDL channel (rtw89 quirk) -> plain monitor
# mode -> OWL in the background (creates awdl0) -> OpenDrop on awdl0.
#
# Usage (from the repository root):
#   sudo bash poc/airdrop-poc.sh find            # list nearby AirDrop devices
#   sudo bash poc/airdrop-poc.sh receive         # be visible, accept files
#   sudo bash poc/airdrop-poc.sh send FILE       # discover for 30 s, send to device 0
#
# The Apple device must have AirDrop set to "Everyone".
# Stop with Ctrl+C: Wi-Fi is always restored and the hotspot profile removed.
# Logs: poc/out/ (git-ignored). Received files land in poc/out/received/.
set -u

IFACE=${IFACE:-wlp2s0}
CHANNEL=${CHANNEL:-149}
DEVICE_NAME=${DEVICE_NAME:-poc}
FIND_SECONDS=${FIND_SECONDS:-30}
HOTSPOT_NAME=poc-hotspot

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR="$REPO/poc/out"
OPENDROP="$REPO/.venv/bin/opendrop"
OWL_LOG="$OUT_DIR/owl.log"

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
[ -x "$OPENDROP" ] || die "OpenDrop not found at $OPENDROP (create .venv first)"

mkdir -p "$OUT_DIR/received"
OWL_PID=

restore() {
    [ -n "$OWL_PID" ] && kill "$OWL_PID" 2>/dev/null && wait "$OWL_PID" 2>/dev/null
    nmcli connection delete "$HOTSPOT_NAME" >/dev/null 2>&1
    ip link set "$IFACE" down
    iw dev "$IFACE" set type managed
    ip link set "$IFACE" up
    nmcli device set "$IFACE" managed yes
    chown -R "$SUDO_USER": "$OUT_DIR"
    echo "Wi-Fi restored. Logs in $OUT_DIR"
}
trap restore EXIT

as_user() {
    sudo -u "$SUDO_USER" -H "$@"
}

opendrop() {
    as_user "$OPENDROP" "$@" -i awdl0 2>&1 | grep -v -e pkg_resources -e 'from pkg_resources'
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

echo "== Starting OWL (log: $OWL_LOG)"
"$OWL_BIN" -i "$IFACE" -c "$CHANNEL" -N -v >"$OWL_LOG" 2>&1 &
OWL_PID=$!

for _ in $(seq 20); do
    ip -6 addr show dev awdl0 2>/dev/null | grep -q inet6 && break
    kill -0 "$OWL_PID" 2>/dev/null || die "OWL exited, see $OWL_LOG"
    sleep 1
done
ip -6 addr show dev awdl0 2>/dev/null | grep -q inet6 || die "awdl0 has no IPv6 address"
echo "awdl0 up: $(ip -6 -br addr show dev awdl0)"

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
        as_user timeout -s INT "$FIND_SECONDS" "$OPENDROP" find -i awdl0 2>&1 | grep -v pkg_resources
        echo "== Sending $file to device 0"
        opendrop send -r 0 -f "$file"
        ;;
esac

echo "== OWL peers seen: $(grep -c 'add peer' "$OWL_LOG")"
