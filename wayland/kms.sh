#!/bin/bash
# mock logind on a private system bus + KMS display server
D=$(dirname "$0")
export XDG_RUNTIME_DIR=/tmp/xdg-$(id -u); mkdir -p -m 700 "$XDG_RUNTIME_DIR"
unset DISPLAY WAYLAND_DISPLAY
export XDG_SESSION_TYPE=wayland XDG_SESSION_ID=c1 XDG_SEAT=seat0 XDG_CURRENT_DESKTOP=GNOME
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/system_bus_socket
rm -f "$XDG_RUNTIME_DIR/system_bus_socket"
dbus-daemon --config-file="$D/system-bus.conf" --address="$DBUS_SYSTEM_BUS_ADDRESS" --nofork --nopidfile 2>"$D/sysbus.log" &
sleep 1
"$D/mock-logind.py" & sleep 1
timeout ${T:-25} dbus-run-session -- sh -c 'echo "$DBUS_SESSION_BUS_ADDRESS" > '"$D"'/session-bus; exec gnome-shell --display-server --wayland --no-x11 '"$*"
echo "gnome-shell rc=$?"; kill %1 %2
