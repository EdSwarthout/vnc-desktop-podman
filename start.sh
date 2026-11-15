#!/bin/bash
set -e

# First-boot setup in the (volume-mounted) home dir

# New home: seed dotfiles from /etc/skel (the volume mount hides what useradd copied)
# and put ~/.local/bin (native Claude install) on PATH for non-login shells too.
if [ ! -f ~/.bashrc ]; then
    cp -r --update=none /etc/skel/. ~/
    mkdir -p ~/.local/bin
    cat >> ~/.bashrc <<'EOF'
if [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin${PATH:+:${PATH}}"
fi
EOF
fi

# Nested instances share their parent's hostname, so the prompt and terminal title
# (\h) would show the parent's name: use this instance's $D_NAME (set by d_run) there.
# Added once, also to existing homes; a no-op where D_NAME is the hostname.
if ! grep -q 'D_NAME' ~/.bashrc; then
    cat >> ~/.bashrc <<'EOF'
# Nested instance: show its name ($D_NAME, from d_run) instead of the shared hostname
if [ -n "${D_NAME:-}" ] && [ "$D_NAME" != "$HOSTNAME" ]; then
    PS1=${PS1//\\h/$D_NAME}
fi
EOF
fi

# Fit /etc/subuid, /etc/subgid and newuidmap's caps to this container's ID map (see
# nested-subids). If the ranges changed, the nested storage in this home may have been
# set up with the old ones: podman system migrate picks up the new ones.
if [ -x /usr/local/sbin/nested-subids ]; then
    old=$(cat /etc/subuid /etc/subgid)
    sudo /usr/local/sbin/nested-subids || echo "start.sh: nested-subids failed; nested podman may not work" >&2
    if [ "$old" != "$(cat /etc/subuid /etc/subgid)" ]; then
        podman system migrate || echo "start.sh: podman system migrate failed" >&2
    fi
    # Nested storage created before /etc/subgid had ed:0:1 has its group IDs one off
    # (REVIEW #28). A marker records storage that's known good; warn if there's no marker
    # but image layers exist (empty storage, e.g. just created by migrate above, is fine).
    m=~/.local/share/containers/.subgid-root-mapped
    if [ ! -e "$m" ]; then
        if grep -qs '"id"' ~/.local/share/containers/storage/overlay-layers/layers.json; then
            echo "start.sh: nested podman storage predates the ed:0:1 subgid mapping;" \
                 "run 'podman system reset' once, then 'touch $m'" >&2
        else
            mkdir -p "${m%/*}" && touch "$m"
        fi
    fi
fi

# Stage "base" has no VNC: stay up for `podman exec` until stopped (--init passes the
# stop signal on to sleep).
if ! command -v vncserver >/dev/null; then
    echo "start.sh: no vncserver in this image (stage base); waiting" >&2
    exec sleep infinity
fi

vncdir=~/.config/tigervnc
mkdir -p "$vncdir"
if [ ! -f "$vncdir/passwd" ]; then
    : "${VNC_PASSWORD:?no $vncdir/passwd and VNC_PASSWORD not set}"
    echo "$VNC_PASSWORD" | vncpasswd -f > "$vncdir/passwd"
    chmod 600 "$vncdir/passwd"
fi
# The session comes from the image (/usr/local/bin/vnc-session: xterm, XFCE or LXQt), so
# a home works with any stage. Write xstartup if it's missing or is the XFCE-only one
# older versions generated; a customised xstartup is left alone.
xstartup_old='#!/bin/sh
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
exec dbus-launch --exit-with-session startxfce4'
xstartup_new='#!/bin/sh
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
exec dbus-launch --exit-with-session /usr/local/bin/vnc-session'
if [ ! -f "$vncdir/xstartup" ] || [ "$(cat "$vncdir/xstartup")" = "$xstartup_old" ]; then
    printf '%s\n' "$xstartup_new" > "$vncdir/xstartup"
    chmod +x "$vncdir/xstartup"
fi

# Run the VNC server (in the foreground, -fg) and websockify side by side. If either
# exits — Xvnc crash, or the session ends (logging out, exiting the xterm) — stop the
# other and exit, so the container stops instead of staying "up" with no desktop.
# `podman logs` says which.
trap 'stopping=1; kill $(jobs -p) 2>/dev/null' TERM INT

# -desktop: the VNC window title; a nested instance's hostname is its parent's.
vncserver :1 -fg -desktop "${D_NAME:-$(hostname)}:1 ($(id -un))" -geometry "$VNC_RESOLUTION" -depth 24 -localhost no -SecurityTypes VncAuth &
vnc_pid=$!

# Browser access: http://localhost:6080/vnc.html
websockify --web=/usr/share/novnc 6080 localhost:5901 &

rc=0
wait -n -p done_pid || rc=$?
if [ -n "$stopping" ]; then
    echo "start.sh: stop signal received; shutting down" >&2
else
    [ "$done_pid" = "$vnc_pid" ] && what=vncserver || what=websockify
    echo "start.sh: $what exited (status $rc); stopping container" >&2
fi
kill $(jobs -p) 2>/dev/null || true
wait || true
exit "$rc"
