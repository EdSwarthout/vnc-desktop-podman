# Desktops

Each desktop as it first comes up: a new home dir, nothing opened, 1440x900
(`VNC_RESOLUTION`). See [Images](../README.md#images) for what each one contains.

`base` is headless, so it has no screenshot. `browser` starts with the same bare
`xterm` as `vnc`. Ubuntu's first, then [Debian's](#debian), [Fedora's](#fedora),
[Arch Linux's](#arch-linux) and [Google Antigravity](#google-antigravity).

# Ubuntu

## `vnc` (and `browser`): xterm
![vnc stage: a bare xterm](ubuntu/vnc.png)

## `xfce`: XFCE
![xfce stage](ubuntu/xfce.png)

## `lxqt`: LXQt
![lxqt stage](ubuntu/lxqt.png)

## `gnome`: GNOME Flashback
![gnome stage](ubuntu/gnome.png)

## `kde`: KDE Plasma
![kde stage](ubuntu/kde.png)

## `mate`: MATE
![mate stage](ubuntu/mate.png)

## `cinnamon`: Cinnamon
![cinnamon stage](ubuntu/cinnamon.png)

# Debian

## `vnc` (and `browser`): xterm
![Debian vnc stage: a bare xterm](debian/vnc.png)

## `gnome`: GNOME Shell
It starts in the Activities overview, as GNOME does.
![Debian gnome stage](debian/gnome.png)

# Fedora

## `vnc` (and `browser`): xterm
![Fedora vnc stage: a bare xterm](fedora/vnc.png)

## `xfce`: XFCE
![Fedora xfce](fedora/xfce.png)

## `lxqt`: LXQt
Fedora's own LXQt defaults: its theme and wallpaper, and an empty quick launch in the panel.
![Fedora lxqt](fedora/lxqt.png)

# Arch Linux

## `vnc` (and `browser`): xterm
![Arch Linux vnc stage: a bare xterm](archlinux/vnc.png)

## `browser`: Chromium
The stage comes up like `vnc`; this is after `d_chrome_bin=chromium d_chrome`, which
opens `chrome://version/`. There is no window manager in this stage, so the
window was moved next to the xterm with `xdotool` for the picture.
![Arch Linux browser stage: the xterm and Chromium showing chrome://version](archlinux/browser.png)

## `openbox`: Openbox
One xterm; the menu (Terminal, Chromium, window list, Exit) is a right-click on the background.
![Arch Linux openbox stage](archlinux/openbox.png)

# Google Antigravity

## `lxqt-antigravity`: Antigravity App, nested
Not a fresh home: an Antigravity instance on an arm64 machine (DGX Spark), seen in
TigerVNC (taken before the instances were named after their images: `ag1u`), with the
Antigravity App signed in, Chrome on antigravity.google, and a nested instance (started
inside it with `d_run`) in its own TigerVNC
window, running the App too. See [container/antigravity/README.md](../container/antigravity/README.md).
![lxqt-antigravity on arm64: the Antigravity App in an instance and in a nested one](antigravity/lxqt-nested.png)

## Retaking them

`d_screenshots N` (from `env.rc`) retakes them all for `$d_distro`
(`d_distro=debian d_screenshots N` for Debian's, `d_distro=fedora`,
`d_distro=archlinux`); `d_screenshots N kde` just
that one. For each target it builds the image, runs it on instance N with a new
home, waits for the desktop to settle, runs `tests/screenshot.sh` inside and
saves the result as `docs/<distro>/<target>.png`, then removes the container and that
home. N must be an unused instance number. The `vnc` stage has no screenshot
tool, so `scrot` is installed in its throwaway container for the picture.
`archlinux/browser.png` and `antigravity/lxqt-nested.png` aren't among these (they
show started apps, not the desktop as it comes up): they were taken by hand, as
described above.
