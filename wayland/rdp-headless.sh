#!/bin/bash
# pipewire + gnome-remote-desktop in headless mode (RDP) in the running shell session: each
# client gets a virtual monitor of its own (run headless.sh with MODE= so it's the only one).
# Unlike rdp.sh, no keyring: headless mode keeps the credentials in
# ~/.local/share/gnome-remote-desktop/credentials.ini (no TPM: "using GKeyFile as fallback")
# and its settings under the org.gnome.desktop.remote-desktop.rdp.headless schema.
. /home/ed/shell/env.sh
D=/home/ed/shell; cd $D
[ -f tls.key ] || openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj /CN=vnc-desktop -out tls.crt -keyout tls.key 2>/dev/null
pipewire > pipewire.log 2>&1 &
sleep 1
wireplumber > wireplumber.log 2>&1 &
sleep 1
G="grdctl --headless"
$G rdp set-tls-cert $D/tls.crt; $G rdp set-tls-key $D/tls.key
# credentials before the daemon starts: changed under a running daemon, logins fail (SEC_E_MESSAGE_ALTERED)
$G rdp set-credentials ed "$(cat $D/rdp-pass)"
$G rdp disable-view-only
# "grdctl --headless rdp enable" wants systemd (gnome-remote-desktop-headless.service)
gsettings set org.gnome.desktop.remote-desktop.rdp.headless enable true
$G status
exec /usr/libexec/gnome-remote-desktop-daemon --headless > grd.log 2>&1
