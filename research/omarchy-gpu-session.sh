#!/bin/bash
# Hyprland nested in a headless labwc, both on the render node; wayvnc on labwc
# Prototype from research/intel-igpu-render-node.md (2026-11-22): not wired into the
# Containerfile. Needs labwc, wlr-randr, wtype (+ wayvnc, foot, grim) in the image and
# --device /dev/dri/renderD128 --group-add keep-groups.
set -u
export XDG_RUNTIME_DIR=/tmp/xdg-$(id -u); mkdir -p -m 700 "$XDG_RUNTIME_DIR"
R=${VNC_RESOLUTION:-1440x900} RN=${RENDER_NODE:-/dev/dri/renderD128}
eval "$(dbus-launch --sh-syntax)"
mkdir -p ~/.config/labwc
cat > ~/.config/labwc/rc.xml <<X
<?xml version="1.0"?>
<labwc_config>
  <core><decoration>client</decoration><gap>0</gap></core>
  <theme><border><width>0</width></border></theme>
  <windowRules><windowRule identifier="*" serverDecoration="no"><action name="Maximize"/></windowRule></windowRules>
</labwc_config>
X
: > ~/.config/labwc/autostart

WLR_BACKENDS=headless WLR_RENDER_DRM_DEVICE=$RN WLR_LIBINPUT_NO_DEVICES=1 labwc -V > /tmp/labwc.log 2>&1 &
for _ in $(seq 50); do [ -S "$XDG_RUNTIME_DIR/wayland-0" ] && break; sleep 0.2; done
P() { WAYLAND_DISPLAY=wayland-0 "$@"; }
P wlr-randr --output HEADLESS-1 --custom-mode "$R"
# Hyprland's output starts disabled (aquamarine renders on the toplevel configure, before
# acking the xdg_surface one: labwc then drops it), and its first commit stays unflushed
# until labwc sends something: a virtual keyboard key does.
mon=/tmp/hypr-monitor.conf; echo "monitor = WAYLAND-1, disable" > $mon
{ cat /etc/omarchy-vnc/hyprland.conf; printf "debug {\n disable_logs = false\n}\n"; echo "source = $mon"; } > /tmp/hypr.conf
P Hyprland --config /tmp/hypr.conf > /tmp/hypr.out 2>&1 &
for _ in $(seq 75); do s=$(ls "$XDG_RUNTIME_DIR"/hypr/*/.socket.sock 2>/dev/null) && break; sleep 0.2; done
export HYPRLAND_INSTANCE_SIGNATURE=$(basename "$(dirname "$s")")
P wtype -k Shift_L; sleep 0.5
echo "monitor = WAYLAND-1, $R, 0x0, 1" > $mon; hyprctl reload >/dev/null
P wayvnc -r 0.0.0.0 5900 > /tmp/wayvnc.log 2>&1 &
sleep 2; WAYLAND_DISPLAY=wayland-1 foot -e sh -c "echo instance ${INST:-$HOSTNAME}; exec bash" > /dev/null 2>&1 &
sleep 2
echo "${INST:-$HOSTNAME}: renderer $(grep -m1 -h 'Renderer:' "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log | sed 's/.*Renderer: //'); labwc $(grep -m1 'EGL driver name' /tmp/labwc.log | sed 's/.*: //'); monitor $(hyprctl -j monitors | tr -d ' \n' | grep -o '"width":[0-9]*,"height":[0-9]*')"
P grim -s 0.5 /tmp/shot.png
grep -c 'wl_display#1.error\|error in client' /tmp/labwc.log | sed 's/^/labwc client errors: /'
