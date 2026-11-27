# . env.sh: a shell inside the instance as a client of the gnomewl prototype's Shell
# (session bus, system bus, Wayland and Xwayland display from gnome-shell's environment)
p=$(pgrep -o -x gnome-shell) || { echo "no gnome-shell" >&2; return 1; }
eval "$(tr '\0' '\n' < /proc/$p/environ | grep -E '^(DBUS_SESSION_BUS_ADDRESS|DBUS_SYSTEM_BUS_ADDRESS|XDG_[A-Z_]+|WAYLAND_DISPLAY)=' | sed 's/^/export /; s/=\(.*\)/="\1"/')"
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}
x=$(ls /tmp/.X11-unix/ | sed -n 's/^X//p' | grep -vx 1 | head -1)
[ -n "$x" ] && export DISPLAY=:$x || unset DISPLAY
XAUTHORITY=$(ls "$XDG_RUNTIME_DIR"/.mutter-Xwaylandauth.* 2>/dev/null | head -n 1); export XAUTHORITY
