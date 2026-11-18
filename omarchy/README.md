# Omarchy in rootless podman, headless, over wayvnc

Status: **experiment**, 2026-11-17. Standalone: its own `Containerfile` and `env.rc`
(prefix `o_`), not wired into the top-level `env.rc`, `start.sh` or `d_test`.
Tested in a nested podman inside an Ubuntu instance (cc8u) with the host's vkms card
passed through.

## Result

Omarchy 4.5.0 (ISO 2026.11.05): Hyprland 0.56 and Omarchy's Quickshell shell (bar, menus,
notifications, lock) run without systemd, on a **vkms** DRM card, rendered on the CPU,
and are shown and driven over **wayvnc** (no password, port 7100+N).

| Stage | What | Screenshot |
|---|---|---|
| `rootfs` | the installed Omarchy system + user, pacman usable; headless | |
| `wayvnc` | + wayvnc and noVNC (websockify, port 6280+N); bare Hyprland (`hyprland-vnc.conf`) with a foot terminal | `wayvnc.png` |
| `omarchy` | + Omarchy's own desktop from the home's config; systemd/uwsm shims | `omarchy.png` |

Checked:
- **Input**: typing and clicking work, the pointer is visible (`wayvnc -r`), through a VNC client, and so do Omarchy's key
  bindings (Super+Return terminal, Super+Space menu).
- **Ending the session**: Omarchy's Log Out/Restart/Shutdown (and `SUPER SHIFT E` in
  `wayvnc`) exit Hyprland, which stops the container. `podman start` brings it back on the same home.
- **Locking**: a lock (Super+Ctrl+L, `omarchy-system-lock`) unlocks with **any character +
  Enter**. A bare Enter does nothing, because the lock screen ignores an empty field.
- **sudo**: refused.

## Running it

```bash
sudo modprobe vkms                     # host, once per boot
omarchy/extract.sh                     # ISO -> omarchy/rootfs.tar (~12 GB scratch, 7.5 GB tar)
source omarchy/env.rc
o_build omarchy                        # builds rootfs -> wayvnc -> omarchy
o_target=omarchy o_run 1               # container ccNo (nested: <instance>_No), home omarchyN
o_vnc                                  # or any VNC client on <host>:7101
o_novnc                                # browser: http://<host>:6281/vnc.html?autoconnect=1
o_screenshot /tmp/s.png; o_exec CMD…; o_logs; o_rm [-f] 1
```

**Super key**: Omarchy is driven with Super (Super+Space menu, Super+Return terminal,
…). In TigerVNC's viewer, press **Ctrl+Alt+G** to toggle keyboard capture. Otherwise
the local desktop may take Super chords (e.g. Super+Space) before they reach the
session. **Works nested too** (checked 2026-11-17): a host TigerVNC viewer on the
outer instance (cc8u `:1`) with keyboard grab on, and in that desktop a `vncviewer`
on the Omarchy container (`o_vnc`). Super chords reach Omarchy through both viewers
(only the outer one needs the grab), **except Super+Space**, which doesn't arrive that way
(something on the outer instance's side keeps it). Open the menu another way meanwhile:
the Omarchy logo in the bar, or `o_exec omarchy-menu toggle root`. Super chords sent by the Claude in Chrome extension through noVNC didn't arrive
(meta+space, meta+Return, or noVNC's Windows-key toggle); the extension is fine for
looking and clicking.

The ISO must be loop-mounted at `omarchy/OMARCHY_202611/` (or `OMARCHY_ISO=…`), and
`/dev/dri/<vkms card>` must be visible where `o_run` runs. A nested run needs the outer
instance created with that device.

## What it needs, and why

- **Rootfs from `omarchy-root.img.zst`**, not `airootfs.sfs`. The `.sfs` is the live
  installer (archinstall, no Hyprland). The `.img.zst` is a raw btrfs filesystem (label
  `omarchy-root-image`; subvolume `omarchy-root` is the system). `extract.sh` reads it
  with `btrfs restore -x -m -S` as root in a throwaway `archcc:base` container: no loop
  mount, no host root. Owners, modes, xattrs and file caps survive. **Setuid bits don't**:
  the `rootfs` stage puts them back from pacman's mtree files.
- **pacman: Omarchy's "stable" channel** (`/usr/share/omarchy/default/pacman/pacman-stable.conf`
  + `mirrorlist-stable`, a dated Arch snapshot plus `[omarchy]`). The image's own `pacman.conf`
  has no `[omarchy]` repo, and its mirrorlist is all commented out. Arch's live mirrors
  break `-Syu`, because Omarchy pins exact versions (`omarchy-hyprland-titlebars` needs
  `hyprland=0.56.2`). Omarchy's pre-transaction hook refuses a plain `pacman -Syu`
  ("Woah partner…"), so each `RUN` sets `OMARCHY_ALLOW_DIRECT_PACMAN=1`. The shared
  pacman cache works as in `../archlinux/` (`CacheDir = /var/cache/apt-archlinux/`, no
  `DownloadUser`).
- **DRM: the vkms card only.** Its number depends on module load order: here card0 was
  the NVIDIA GPU and vkms was card2. `o_run` finds the vkms card itself (`/sys/class/drm/card*`
  → `…/vkms/…`) and refuses any other unless `o_card=… o_allow_gpu=1`. Mesa renders on
  the CPU (kms_swrast).
- **No logind/seatd**: `LIBSEAT_BACKEND=noop` makes libseat open the card directly.
  A private session bus comes from `dbus-launch`. `XDG_RUNTIME_DIR=/tmp/xdg-$UID`.
- **`omarchy-session`** (CMD) starts Hyprland and waits for its socket, then runs
  `wayvnc -r -o <output> 0.0.0.0 5900`. It exits when either one does. `-r`
  (`--render-cursor`) draws the pointer into the frames: without it the mouse worked,
  but the pointer was invisible in the client. `WAYVNC_OPTS` replaces the options;
  set it empty to drop `-r`.
  - **Resolution** is `$VNC_RESOLUTION` (1440x900); vkms prefers 1024x768.
    `hyprctl keyword` doesn't work with Lua configs ("Use eval"), and an eval at startup
    is undone by Omarchy's config reloads. So on a new home the session edits the
    seeded `~/.config/hypr/monitors.lua`: `mode = os.getenv("VNC_RESOLUTION") or
    "preferred"`, and GDK scale 1.
- **Pointer hiding**: Omarchy sets `cursor.hide_on_key_press = true`, so tapping
  Super hid the pointer until the mouse moved. At every start the session appends
  `hl.config({ cursor = { hide_on_key_press = false } })` to the home's
  `~/.config/hypr/looknfeel.lua`, unless that file already mentions the setting.
- **Home** (a volume): the first boot copies `/etc/skel` (Omarchy's configs, Lua
  Hyprland config) and sets Omarchy's "stay awake" idle toggle (Super+Ctrl+I).
- **Shims in `/usr/local/bin`** (`shims/`) stand in for systemd/uwsm:
  - `uwsm-app` / `uwsm-terminal`: Omarchy's launcher for everything; starts the
    command detached (`-T`: in a terminal).
  - `systemd-run`: detached, or in the foreground with `--wait`/`--scope`;
    `--on-active` delays; calendar timers are dropped.
  - `systemd-cat`: runs the command, output to `podman logs` with the tag.
  - `uwsm stop` and `systemctl poweroff|reboot`: `hypr-exit`. Suspend does nothing.
  - `hypr-exit`: `hyprctl dispatch 'hl.dsp.exit()'` (Lua configs reject plain `exit`),
    or else `exit`.
- **Lock PAM service** `/etc/pam.d/omarchy-lock-password` = `pam_permit`. Omarchy's
  installer normally writes it as root (`omarchy-apply-lock`). Without it PAM's
  `other` denies everything, and a locked session could never be unlocked (the user
  has no password).

## Not done / open

- No VNC password (fine for now), so noVNC connects with `?autoconnect=1` and no prompt.
- Nested podman, Claude Code (`install_claude`), the shared `start.sh`/`nested-subids`:
  not added.
- Image size: the rootfs is Omarchy's full install (LibreOffice, Chromium, Electron, fonts…),
  7.5 GB. Nothing is trimmed.
- The first-run notifications (Wi-Fi, Git) and Omarchy features that need systemd user
  units, NetworkManager, PipeWire, power-profiles-daemon and so on are untested. They
  probably fail quietly.
- A bare Enter doesn't dismiss the lock screen (any character + Enter does).
- Testing from a desktop inside an instance: that desktop may take Super+Space itself.
  TigerVNC's Ctrl+Alt+G keyboard grab on the outer viewer passes every Super chord but
  Super+Space (see "Super key" above); for scripted checks, send keys straight over RFB.
- Only one instance at a time per vkms card (single DRM master).
