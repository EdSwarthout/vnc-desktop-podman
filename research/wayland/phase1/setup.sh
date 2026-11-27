#!/bin/bash
# Run on the parent, after `source env.rc; d_select N; d_target=gnome d_run` (a nested
# vnc-desktop-ubuntu:gnome-2604 instance): installs the Phase 1 packages as root, copies
# this directory to ~/phase1 in the instance's home, and makes its xstartup run the
# gnomewl prototype instead of Flashback. Then restarts the instance.
# Needs $d_name and $d_home (from d_select). PKGS adds packages.
set -e
D=$(dirname "$(readlink -f "$0")")
: "${d_name:?d_select first}" "${d_home:?}"
pkgs="dbus-x11 freerdp3-x11 gnome-keyring gnome-remote-desktop gnome-settings-daemon
      gnome-shell gnome-terminal nautilus openssl pipewire python3-dbus python3-gi
      wireplumber xwayland $PKGS"
# shellcheck disable=SC2086
podman exec -u root "$d_name" sh -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y -q --no-install-recommends $(echo $pkgs)" | tail -3
rm -rf "$d_home/phase1"; cp -r "$D" "$d_home/phase1"
x=$d_home/.config/tigervnc/xstartup
printf '%s\n' '#!/bin/sh' 'unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS' \
    'exec dbus-launch --exit-with-session "$HOME/phase1/gnomewl-session"' > "$x"
chmod +x "$x"
podman restart -t 5 "$d_name"
