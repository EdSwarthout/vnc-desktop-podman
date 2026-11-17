#!/bin/bash
# headless backend + private system bus; MOCK=1 adds the mock logind. No fake /run files, no card0 use.
D=$(dirname "$0")
export XDG_RUNTIME_DIR=/tmp/xdg-$(id -u); mkdir -p -m 700 "$XDG_RUNTIME_DIR"
unset DISPLAY WAYLAND_DISPLAY XDG_SESSION_ID XDG_SEAT
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/system_bus_socket
rm -f "$XDG_RUNTIME_DIR/system_bus_socket"
dbus-daemon --config-file="$D/system-bus.conf" --address="$DBUS_SYSTEM_BUS_ADDRESS" --nofork --nopidfile 2>"$D/sysbus.log" &
sleep 1
[ "${MOCK:-0}" = 1 ] && { "$D/mock-logind.py" & sleep 1; }
timeout ${T:-25} dbus-run-session -- sh -c 'echo "$DBUS_SESSION_BUS_ADDRESS" > '"$D"'/session-bus; exec gnome-shell --headless --wayland --no-x11 --virtual-monitor '"${MODE:-1440x900}"
echo "gnome-shell rc=$?"; kill $(jobs -p)
