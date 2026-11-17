#!/bin/bash
# pipewire + gnome-remote-desktop (RDP, mirrors the vkms monitor) in the running shell session
. /home/ed/shell/env.sh
D=/home/ed/shell; cd $D
[ -f tls.key ] || openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj /CN=vnc-desktop -out tls.crt -keyout tls.key 2>/dev/null
pipewire > pipewire.log 2>&1 &
sleep 1
wireplumber > wireplumber.log 2>&1 &
sleep 1
grdctl rdp set-tls-cert $D/tls.crt; grdctl rdp set-tls-key $D/tls.key
grdctl rdp set-credentials ed "$(cat $D/rdp-pass)"
grdctl rdp disable-view-only; grdctl rdp enable
gsettings set org.gnome.desktop.remote-desktop.rdp enable true   # "grdctl rdp enable" needs systemd
grdctl status
exec /usr/libexec/gnome-remote-desktop-daemon > grd.log 2>&1
