#!/usr/bin/env bash
# Run OWL on wlp2s0 (AWDL channel 149) in the foreground.
# rtw89 quirks handled here:
#   - no *active* monitor mode: plain monitor mode is set here, OWL runs with -N;
#   - monitor mode only receives on the channel the firmware last operated on:
#     a short-lived hotspot on the AWDL channel is started first.
# Stop with Ctrl+C: Wi-Fi is always restored and the hotspot profile removed.
set -u

IFACE=wlp2s0
CHANNEL=149
HOTSPOT_NAME=poc-test
OWL_BIN=/home/abiernacki/.local/src/owl/build/daemon/owl
LOG=/home/abiernacki/owl-test.log

restore() {
    nmcli connection delete "$HOTSPOT_NAME" >/dev/null 2>&1
    ip link set "$IFACE" down
    iw dev "$IFACE" set type managed
    ip link set "$IFACE" up
    nmcli device set "$IFACE" managed yes
    chown "${SUDO_USER:-root}": "$LOG" 2>/dev/null
    echo "Wi-Fi restored."
}
trap restore EXIT

nmcli device wifi hotspot ifname "$IFACE" con-name "$HOTSPOT_NAME" \
    ssid "$HOTSPOT_NAME" band a channel "$CHANNEL" password "poc-test-pw" >/dev/null
sleep 5
nmcli connection down "$HOTSPOT_NAME" >/dev/null

nmcli device set "$IFACE" managed no
ip link set "$IFACE" down
iw dev "$IFACE" set type monitor
ip link set "$IFACE" up
iw dev "$IFACE" set channel "$CHANNEL"

"$OWL_BIN" -i "$IFACE" -c "$CHANNEL" -N -v 2>&1 | tee "$LOG"
