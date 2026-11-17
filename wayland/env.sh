export XDG_RUNTIME_DIR=/tmp/xdg-$(id -u) WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME
export DBUS_SESSION_BUS_ADDRESS=$(cat /home/ed/shell/session-bus) DBUS_SYSTEM_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/system_bus_socket
unset DISPLAY
