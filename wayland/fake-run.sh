#!/bin/sh
# as root: the /run files libsystemd and libudev read (no logind, no udevd here)
# usage: fake-run.sh [UID [CARD]]: CARD (e.g. card1) gets the seat tag, by default the vkms
# card (found in /sys/class/drm; its number depends on load order: card0 on hwd23, card1 on
# the DGX Spark, whose card0 is the NVIDIA GPU). Only that card is tagged, which hides the
# host's other cards visible in /sys from mutter.
U=${1:-1001}
C=${2:-$(for c in /sys/class/drm/card[0-9]*; do
    case ${c##*/} in *-*) continue;; esac   # connectors (card0-Virtual-1)
    case $(readlink -f "$c") in */vkms/drm/card[0-9]*) basename "$c"; break;; esac
done)}
[ -n "$C" ] || { echo "no vkms card in /sys/class/drm (host: modprobe vkms), and no CARD given" >&2; exit 1; }
DEV=$(cat "/sys/class/drm/$C/dev" 2>/dev/null) || { echo "$C: no /sys/class/drm/$C/dev" >&2; exit 1; }
[ -e "/dev/dri/$C" ] || echo "warning: /dev/dri/$C isn't in this container (--device /dev/dri/$C)" >&2
echo "seat0 card: $C ($DEV)"
mkdir -p /run/systemd/users /run/systemd/sessions /run/systemd/seats /run/udev/data /run/udev/tags/seat
printf '%s\n' NAME=ed STATE=active DISPLAY=c1 SESSIONS=c1 ACTIVE_SESSIONS=c1 ONLINE_SESSIONS=c1 SEATS=seat0 ACTIVE_SEATS=seat0 ONLINE_SEATS=seat0 > /run/systemd/users/$U
printf '%s\n' UID=$U USER=ed ACTIVE=1 IS_DISPLAY=1 STATE=active REMOTE=0 TYPE=wayland CLASS=user SEAT=seat0 > /run/systemd/sessions/c1
printf '%s\n' IS_SEAT0=1 CAN_MULTI_SESSION=1 CAN_TTY=0 CAN_GRAPHICAL=1 ACTIVE=c1 ACTIVE_UID=$U SESSIONS=c1 UIDS=$U > /run/systemd/seats/seat0
printf '%s\n' I:1 E:ID_SEAT=seat0 E:ID_FOR_SEAT=drm-vkms G:seat G:master-of-seat Q:seat Q:master-of-seat V:1 > /run/udev/data/c$DEV
: > /run/udev/tags/seat/c$DEV
