#!/bin/bash
# screenshot.sh [FILE.png]: full-screen PNG of the VNC display ($DISPLAY, :1), taken
# inside an instance with the desktop stage's own tool; prints the file's path.
# xfce: xfce4-screenshooter. lxqt: screengrab (it picks the folder and name itself, so
# the newest PNG it wrote is moved to FILE). gnome (Ubuntu and Debian): gnome-screenshot.
# kde: spectacle. mate, cinnamon: scrot. Other stages have no tool: exit 2.
set -euo pipefail
export DISPLAY=${DISPLAY:-:1}
out=${1:-/tmp/screenshot-$(date +%Y%m%d-%H%M%S).png}

if command -v xfce4-screenshooter >/dev/null; then
    xfce4-screenshooter -f -s "$out"
elif command -v screengrab >/dev/null; then
    stamp=$(mktemp)
    screengrab -f -n
    shot=$(find ~ /tmp -maxdepth 3 -name '*.png' -newer "$stamp" -printf '%T@ %p\n' 2>/dev/null \
           | sort -n | tail -1 | cut -d' ' -f2-)
    rm -f "$stamp"
    [ -n "$shot" ] || { echo "screenshot.sh: screengrab saved no PNG" >&2; exit 1; }
    [ "$shot" = "$out" ] || mv "$shot" "$out"
elif command -v gnome-screenshot >/dev/null; then
    gnome-screenshot -f "$out"
elif command -v spectacle >/dev/null; then
    spectacle -b -n -f -o "$out"
elif command -v scrot >/dev/null; then
    scrot -o "$out"
elif command -v grim >/dev/null; then
    senv="/tmp/runtime-$(id -u)/session.env"
    if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -r "$senv" ]; then
        set -a
        # shellcheck source=/dev/null
        . "$senv"
        set +a
    fi
    grim "$out"
else
    echo "screenshot.sh: no xfce4-screenshooter, screengrab, gnome-screenshot, spectacle, scrot or grim in this stage" >&2
    exit 2
fi
[ -s "$out" ] || { echo "screenshot.sh: $out is missing or empty" >&2; exit 1; }
echo "$out"
