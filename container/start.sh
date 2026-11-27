#!/bin/bash
set -e

# Capabilities added with `podman run --cap-add` (e.g. NET_RAW, for ping) are ambient for
# the non-root user, so every process of the session holds them, and bwrap then refuses to
# run ("Unexpected capabilities but not setuid"): desktops load icons through gdk-pixbuf ->
# glycin -> bwrap, so that fails and the session aborts. Clear them from the ambient set;
# they stay in the bounding set, so programs with file caps (ping: cap_net_raw=ep) still
# get them.
if [ "$(awk '/^CapAmb:/ { print $2 }' /proc/self/status)" != 0000000000000000 ]; then
    exec setpriv --inh-caps=-all --ambient-caps=-all "$0" "$@"
fi

# SHELL: nothing sets it (podman starts this without a login), so the whole session lacked
# it, and programs that take the user's shell from $SHELL fell back to /bin/sh (OpenCode's
# terminal: dash with a bare "$ " prompt). Use the passwd entry's shell, as login would.
SHELL=$(getent passwd "$(id -u)" | cut -d: -f7)
export SHELL=${SHELL:-/bin/bash}

# First-boot setup in the (volume-mounted) home dir

# New home: seed dotfiles from /etc/skel (the volume mount hides what useradd copied)
# and put ~/.local/bin (native Claude install) on PATH for non-login shells too. Last,
# the image's user_files/<distro> (see the Containerfiles' base stage), only here, on
# first boot: they replace what's there (e.g. a .bashrc of your own), but the home
# dir's own mode is kept.
if [ ! -f ~/.bashrc ]; then
    cp -r --update=none /etc/skel/. ~/
    mkdir -p ~/.local/bin
    if ! grep -q '\.local/bin' ~/.bashrc 2>/dev/null; then
        cat >> ~/.bashrc <<'EOF'
if [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin${PATH:+:${PATH}}"
fi
EOF
    fi
    if [ -f /usr/local/share/user_files.tar ]; then
        tar -C ~ -xf /usr/local/share/user_files.tar --no-overwrite-dir \
            || echo "start.sh: unpacking user_files.tar failed" >&2
    fi
fi

# Nested instances share their parent's hostname, so the prompt and terminal title
# (\h) would show the parent's name: use this instance's $D_NAME (set by d_run) there.
# Added once, also to existing homes (unless the .bashrc has it, e.g. from user_files);
# a no-op where D_NAME is the hostname. Only when D_NAME is set (d_run sets it).
if [ -n "${D_NAME:-}" ] && ! grep -q 'D_NAME' ~/.bashrc; then
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
fi

# Stage "base" has no display server: stay up for `podman exec` until stopped (--init
# passes the stop signal on to sleep).
if ! command -v vncserver >/dev/null && [ ! -x /usr/local/bin/vnc-wayland ]; then
    echo "start.sh: no vncserver or vnc-wayland in this image (stage base); waiting" >&2
    exec sleep infinity
fi

vncdir=~/.config/tigervnc
mkdir -p "$vncdir"
# First boot: make passwd from passwd.init, which d_run left in the home (or from
# $VNC_PASSWORD, for a plain `podman run -e`). -s, not -f: a failed vncpasswd leaves an
# empty file. Either way the clear-text copies go: the file is deleted and the variable
# isn't passed on to the VNC server and the desktop.
pw=
if [ ! -s "$vncdir/passwd" ]; then
    if [ -s "$vncdir/passwd.init" ]; then
        pw=$(cat "$vncdir/passwd.init")
    else
        pw=${VNC_PASSWORD:?no $vncdir/passwd or passwd.init, and VNC_PASSWORD not set}
    fi
    ( umask 077; printf '%s\n' "$pw" | vncpasswd -f > "$vncdir/passwd" )
fi
# Wayland/RDP credentials (stored mode 600 under ~/.config/vnc-desktop when needed by the
# image, derived from passwd.init on first boot or a random password in nested copies).
if [ -x /usr/local/bin/vnc-wayland ] && [ ! -s ~/.config/vnc-desktop/wayvnc-pass ]; then
    (
        umask 077
        mkdir -p ~/.config/vnc-desktop
        printf '%s\n' "${pw:-$(openssl rand -base64 12)}" > ~/.config/vnc-desktop/wayvnc-pass
    )
fi
if [ -x /usr/libexec/gnome-remote-desktop-daemon ] && [ ! -s ~/.config/vnc-desktop/rdp-pass ]; then
    (
        umask 077
        mkdir -p ~/.config/vnc-desktop
        printf '%s\n' "${pw:-$(openssl rand -base64 12)}" > ~/.config/vnc-desktop/rdp-pass
    )
fi
rm -f "$vncdir/passwd.init"
unset VNC_PASSWORD pw
# The session comes from the image (/usr/local/bin/vnc-session: an xterm or a desktop),
# so a home works with any image. Write xstartup if it's missing; a customised one is
# left alone.
if [ ! -x /usr/local/bin/vnc-wayland ] && [ ! -f "$vncdir/xstartup" ]; then
    printf '%s\n' '#!/bin/sh' 'unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS' \
        'exec dbus-launch --exit-with-session /usr/local/bin/vnc-session' > "$vncdir/xstartup"
    chmod +x "$vncdir/xstartup"
fi

# Run the VNC server (or vnc-wayland) and websockify side by side. If either exits —
# server crash, or the session ends (logging out, exiting the xterm) — stop the other
# and exit, so the container stops instead of staying "up" with no desktop.
# `podman logs` says which.
_kill_jobs() {
    local p
    for p in $(jobs -p); do kill "$p" 2>/dev/null || true; done
}
trap 'stopping=1; _kill_jobs' TERM INT

if [ -x /usr/local/bin/vnc-wayland ]; then
    /usr/local/bin/vnc-wayland &
    vnc_pid=$!
    vnc_name=vnc-wayland
else
    # -desktop: the VNC window title; a nested instance's hostname is its parent's.
    vncserver :1 -fg -desktop "${D_NAME:-$(hostname)}:1 ($(id -un))" -geometry "${VNC_RESOLUTION:-1440x900}" -depth 24 -localhost no -SecurityTypes VncAuth &
    vnc_pid=$!
    vnc_name=vncserver
fi

# Browser access: http://localhost:6080/vnc.html
# Listen on [::], which takes IPv4 too (bindv6only is 0), so the published port also
# works over IPv6, e.g. via localhost = ::1; IPv4 only if the container has no IPv6.
listen=6080
if [ -n "$(cat /proc/net/if_inet6 2>/dev/null)" ] && [ "$(cat /proc/sys/net/ipv6/bindv6only 2>/dev/null)" = 0 ]; then
    listen='[::]:6080'
fi
websockify --web=/usr/share/novnc "$listen" 127.0.0.1:5901 &

rc=0
wait -n -p done_pid || rc=$?
if [ -n "$stopping" ]; then
    echo "start.sh: stop signal received; shutting down" >&2
else
    [ "$done_pid" = "$vnc_pid" ] && what=$vnc_name || what=websockify
    echo "start.sh: $what exited (status $rc); stopping container" >&2
fi
_kill_jobs
wait || true
exit "$rc"
