# Desktops

Each stage's desktop as it first comes up: a new home dir, nothing opened,
1440x900 (`VNC_RESOLUTION`). See [Stages](../README.md#stages) for what each one
contains.

`base` is headless, so it has no screenshot. `chrome` starts with the same
bare `xterm` as `vnc`.

## `vnc` (and `chrome`): xterm
![vnc stage: a bare xterm](vnc.png)

## `xfce`: XFCE
![xfce stage](xfce.png)

## `lxqt`: LXQt
![lxqt stage](lxqt.png)

## `gnome`: GNOME Flashback
![gnome stage](gnome.png)

## `kde`: KDE Plasma
![kde stage](kde.png)

## `mate`: MATE
![mate stage](mate.png)

## `cinnamon`: Cinnamon
![cinnamon stage](cinnamon.png)

## Retaking them

`d_screenshots N` (from `env.rc`) retakes them all; `d_screenshots N kde` just
that one. For each stage it builds the image, runs it on instance N with a new
home, waits for the desktop to settle, runs `tests/screenshot.sh` inside and
saves the result as `docs/<stage>.png`, then removes the container and that
home. N must be an unused instance number. The `vnc` stage has no screenshot
tool, so `scrot` is installed in its throwaway container for the picture.
