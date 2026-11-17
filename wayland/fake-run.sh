#!/bin/sh
# as root: the /run files libsystemd and libudev read (no logind, no udevd here)
U=${1:-1001}; mkdir -p /run/systemd/users /run/systemd/sessions /run/systemd/seats /run/udev/data /run/udev/tags/seat
printf '%s\n' NAME=ed STATE=active DISPLAY=c1 SESSIONS=c1 ACTIVE_SESSIONS=c1 ONLINE_SESSIONS=c1 SEATS=seat0 ACTIVE_SEATS=seat0 ONLINE_SEATS=seat0 > /run/systemd/users/$U
printf '%s\n' UID=$U USER=ed ACTIVE=1 IS_DISPLAY=1 STATE=active REMOTE=0 TYPE=wayland CLASS=user SEAT=seat0 > /run/systemd/sessions/c1
printf '%s\n' IS_SEAT0=1 CAN_MULTI_SESSION=1 CAN_TTY=0 CAN_GRAPHICAL=1 ACTIVE=c1 ACTIVE_UID=$U SESSIONS=c1 UIDS=$U > /run/systemd/seats/seat0
printf '%s\n' I:1 E:ID_SEAT=seat0 E:ID_FOR_SEAT=drm-vkms G:seat G:master-of-seat Q:seat Q:master-of-seat V:1 > /run/udev/data/c226:0
: > /run/udev/tags/seat/c226:0
