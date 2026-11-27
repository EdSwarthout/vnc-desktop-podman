#!/bin/bash
# lock.sh: check that the screen of the VNC display ($DISPLAY, :1) can't be locked (the
# user has no password, so a locked screen couldn't be unlocked). Run inside an instance
# with the session's D-Bus address, e.g. from the host with `d_exec -s`; d_test does.
# ONLY IN A THROWAWAY INSTANCE: where locking does work, this locks its screen.
#
# It asks for a lock in every way it knows (the screensaver D-Bus interfaces, the
# desktops' lock commands, the usual keyboard shortcuts) and after each one types a line
# into an xterm of its own with xdotool (XTEST, which a locker's keyboard grab diverts,
# unlike events sent to the window). The line arriving means the screen isn't locked.
# Prints ok/FAIL per request, exits non-zero if any failed. Needs xdotool and xterm
# (stage vnc has both).
set -u

# Wayland wlroots branch (labwc): no Xvnc server, uses foot + wtype.
if [ "${XDG_SESSION_TYPE:-}" = wayland ] && [ -n "${WAYLAND_DISPLAY:-}" ] && ! command -v gnome-shell >/dev/null; then
    for c in foot wtype; do
        command -v "$c" >/dev/null || { echo "lock.sh: no $c in this Wayland image" >&2; exit 2; }
    done
    fails=0 n=0
    for locker in swaylock hyprlock gtklock waylock; do
        if command -v "$locker" >/dev/null; then
            echo "FAIL locker installed: $locker"; fails=$((fails + 1))
        fi
    done
    tmp=$(mktemp -d)
    # shellcheck disable=SC2016  # expanded by the inner sh inside foot
    foot sh -c 'while read -r l; do echo "$l" >> "$1"; done' sh "$tmp/typed" &
    term_pid=$!
    trap 'kill "$term_pid" 2>/dev/null; rm -rf "$tmp"' EXIT
    sleep 1
    wl_typed() {
        local try
        for try in 1 2 3; do
            wtype "$1" -k Return 2>/dev/null || true
            for _ in $(seq 10); do
                if grep -q "$1" "$tmp/typed" 2>/dev/null; then return 0; fi
                sleep 0.2
            done
        done
        return 1
    }
    wl_try() {
        local name=$1; shift
        timeout 5 "$@" >/dev/null 2>&1 </dev/null
        sleep 2
        n=$((n + 1))
        if wl_typed "token$n"; then echo "ok   $name"; else echo "FAIL $name: typing no longer reaches the desktop"; fails=$((fails + 1)); fi
    }
    wl_typed token0 || { echo "lock.sh: typing doesn't reach foot even before a lock request" >&2; exit 1; }
    if command -v dbus-send >/dev/null && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        while read -r dest path; do
            wl_try "D-Bus $dest.Lock ($path)" dbus-send --session --type=method_call --dest="$dest" "$path" "$dest.Lock"
        done <<'EOF'
org.freedesktop.ScreenSaver /ScreenSaver
org.freedesktop.ScreenSaver /org/freedesktop/ScreenSaver
EOF
    fi
    for cmd in "xdg-screensaver lock" "loginctl lock-session"; do
        command -v "${cmd%% *}" >/dev/null || continue
        # shellcheck disable=SC2086
        wl_try "$cmd" $cmd
    done
    wl_try "keys super+l" wtype -M logo -k l -m logo
    echo "$fails failed"
    [ "$fails" -eq 0 ]
    exit
fi

# GNOME Wayland bridge branch (gnomewl): gnome-shell runs headless with Xwayland on $DISPLAY
# (e.g. :0) while the full-screen xfreerdp3 bridge runs on Xvnc :1. Open the test xterm on
# Xwayland inside the Shell, close GNOME's overview, and type through the :1 bridge with xdotool.
if [ "${XDG_SESSION_TYPE:-}" = wayland ] && command -v gnome-shell >/dev/null; then
    for c in xdotool xterm; do
        command -v "$c" >/dev/null || { echo "lock.sh: no $c in this image" >&2; exit 2; }
    done
    fails=0 n=0
    tmp=$(mktemp -d)
    title=lock-test-$$
    # shellcheck disable=SC2016  # expanded by the inner sh inside xterm
    xterm -T "$title" -geometry 40x4+100+100 -e sh -c 'while read -r l; do echo "$l" >> "$1"; done' sh "$tmp/typed" &
    xterm_pid=$!
    trap 'kill "$xterm_pid" 2>/dev/null; rm -rf "$tmp"' EXIT
    sleep 2
    gwl_typed() {
        local try bwin
        for try in 1 2 3; do
            if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
                dbus-send --session --print-reply --dest=org.gnome.Shell /org/gnome/Shell \
                    org.freedesktop.DBus.Properties.Set string:org.gnome.Shell \
                    string:OverviewActive variant:boolean:false >/dev/null 2>&1 || true
                sleep 1
            fi
            bwin=$(DISPLAY=:1 xdotool search --onlyvisible --name . 2>/dev/null | head -1 || true)
            [ -n "$bwin" ] && DISPLAY=:1 xdotool windowfocus "$bwin" 2>/dev/null || true
            sleep 0.5
            DISPLAY=:1 xdotool type --delay 25 "$1"
            DISPLAY=:1 xdotool key Return
            for _ in $(seq 10); do
                if grep -q "$1" "$tmp/typed" 2>/dev/null; then return 0; fi
                sleep 0.3
            done
        done
        return 1
    }
    gwl_try() {
        local name=$1; shift
        timeout 5 "$@" >/dev/null 2>&1 </dev/null || true
        sleep 2
        n=$((n + 1))
        if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] \
           && dbus-send --session --print-reply --dest=org.gnome.ScreenSaver \
              /org/gnome/ScreenSaver org.gnome.ScreenSaver.GetActive 2>/dev/null | grep -q 'boolean true'; then
            echo "FAIL $name: org.gnome.ScreenSaver.GetActive is true"
            fails=$((fails + 1))
        elif gwl_typed "token$n"; then
            echo "ok   $name"
        else
            echo "FAIL $name: typing no longer reaches the desktop"
            fails=$((fails + 1))
        fi
    }
    gwl_typed token0 || { echo "lock.sh: typing doesn't reach the test xterm through the bridge" >&2; exit 1; }
    if command -v dbus-send >/dev/null && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        while read -r dest path; do
            gwl_try "D-Bus $dest.Lock ($path)" dbus-send --session --type=method_call --dest="$dest" "$path" "$dest.Lock"
        done <<'EOF'
org.freedesktop.ScreenSaver /ScreenSaver
org.freedesktop.ScreenSaver /org/freedesktop/ScreenSaver
org.gnome.ScreenSaver /org/gnome/ScreenSaver
EOF
    fi
    gwl_try "keys super+l" env DISPLAY=:1 xdotool key super+l
    echo "$fails failed"
    [ "$fails" -eq 0 ]
    exit
fi

export DISPLAY=${DISPLAY:-:1}
for c in xdotool xterm; do
    command -v "$c" >/dev/null || { echo "lock.sh: no $c in this image" >&2; exit 2; }
done

tmp=$(mktemp -d)
title=lock-test-$$
# shellcheck disable=SC2016  # expanded by the inner sh inside xterm
xterm -T "$title" -geometry 40x4+50+50 -e sh -c 'while read -r l; do echo "$l" >> "$1"; done' sh "$tmp/typed" &
xterm_pid=$!
trap 'kill $xterm_pid 2>/dev/null; rm -rf "$tmp"' EXIT
for _ in $(seq 20); do
    # by PID too: GNOME Shell's frame window has the same title
    win=$(xdotool search --all --pid "$xterm_pid" --name "^$title\$" 2>/dev/null | head -1)
    [ -n "$win" ] && break
    sleep 0.5
done
[ -n "${win:-}" ] || { echo "lock.sh: the test xterm didn't come up" >&2; exit 1; }

# typed TOKEN: focus the xterm, type TOKEN + Return, and see whether it arrived. Up to
# three tries, as a desktop that is still starting may move the focus (retrying can't
# get past a locker).
typed() {
    local try
    for try in 1 2 3; do
        # GNOME Shell starts in its overview (and returns to it when the last window
        # closes), where typing goes to the search field and windowactivate doesn't
        # help: close it (no-op elsewhere). --print-reply: the Shell ignores the call
        # if the caller has gone before it has looked at it.
        if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
            dbus-send --session --print-reply --dest=org.gnome.Shell /org/gnome/Shell org.freedesktop.DBus.Properties.Set \
                string:org.gnome.Shell string:OverviewActive variant:boolean:false >/dev/null 2>&1
            sleep 1
        fi
        # Without a window manager (stages vnc, chrome) activate fails: set the focus
        # directly. Not both: under GNOME Shell windowfocus takes the focus away again.
        xdotool windowactivate "$win" 2>/dev/null || xdotool windowraise "$win" windowfocus "$win" 2>/dev/null
        sleep 0.5
        xdotool type --delay 20 "$1"
        xdotool key Return
        for _ in $(seq 10); do
            if grep -q "$1" "$tmp/typed" 2>/dev/null; then
                [ "$try" -eq 1 ] || echo "lock.sh: $1 arrived at try $try" >&2
                return 0
            fi
            sleep 0.3
        done
    done
    return 1
}

fails=0 n=0
# try NAME COMMAND...: one lock request (its own failure doesn't matter: most desktops
# know only a few of them), then the typing test
try() {
    local name=$1; shift
    timeout 5 "$@" >/dev/null 2>&1 </dev/null
    sleep 3
    n=$((n + 1))
    if typed "token$n"; then echo "ok   $name"; else echo "FAIL $name: typing no longer reaches the desktop"; fails=$((fails + 1)); fi
}

typed token0 || { echo "lock.sh: typing doesn't reach the test xterm even before a lock request" >&2; exit 1; }

# D-Bus: a call may start the screensaver by activation, which is the point
if command -v dbus-send >/dev/null && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    while read -r dest path; do
        try "D-Bus $dest.Lock ($path)" dbus-send --session --type=method_call --dest="$dest" "$path" "$dest.Lock"
    done <<'EOF'
org.freedesktop.ScreenSaver /ScreenSaver
org.freedesktop.ScreenSaver /org/freedesktop/ScreenSaver
org.gnome.ScreenSaver /org/gnome/ScreenSaver
org.cinnamon.ScreenSaver /org/cinnamon/ScreenSaver
org.mate.ScreenSaver /
org.xfce.ScreenSaver /
EOF
else
    echo "skip D-Bus lock requests: no dbus-send or no DBUS_SESSION_BUS_ADDRESS (use d_exec -s)"
fi

# The desktops' own commands, where installed
while read -r cmd; do
    command -v "${cmd%% *}" >/dev/null || continue
    # shellcheck disable=SC2086  # the arguments are meant to split
    try "$cmd" $cmd
done <<'EOF'
xflock4
xdg-screensaver lock
loginctl lock-session
gnome-screensaver-command --lock
mate-screensaver-command --lock
cinnamon-screensaver-command --lock
xfce4-screensaver-command --lock
lxqt-leave --lockscreen
EOF

for keys in super+l ctrl+alt+l; do
    try "keys $keys" xdotool key "$keys"
done

echo "$fails failed"
[ "$fails" -eq 0 ]
