# Headless Omarchy in rootless podman over wayvnc: starting notes

Status: **superseded** by `../omarchy/` (2026-11-17). This merges the two
starting notes that were in `logs/`:
- `setup-headless-podman-omarchy.md`: the original recipe, using the online installer;
- `setup-headless-podman-omarchy-from-iso.md`: the revision once the installer was retired.

Both were AI-generated suggestions, not tested instructions. Each section below gives
what they suggested, then **what actually happened** when it was built (see
`../omarchy/README.md` for the working setup).

## 1. Getting Omarchy into an image

**Suggested (original):** `FROM archlinux:base-devel`, install `systemd dbus wayvnc git
wget sudo mesa vulkan-swrast`, add a user `omarchy` with passwordless sudo via `wheel`, then
`RUN wget -qO- https://omarchy.org/install | bash` as that user. If the installer wants a
TTY or systemd services (it installs and waits for Docker), run it in an interactive
systemd container and `podman commit`.

**Suggested (from ISO):** the online installer was retired in June 2026; Omarchy (4.5.0)
ships only as an ISO. Unpack the ISO (`7z x`), then `unsquashfs` its
`arch/x86_64/airootfs.sfs` (or EROFS) into `./omarchy-rootfs`. `FROM scratch` +
`ADD ./omarchy-rootfs /`, then `pacman-key --init/--populate`,
`pacman -Syu wayvnc mesa vulkan-swrast`, and add the user if the live ISO has only its live
user. Watch for live-boot autologin hooks and first-boot wizards in
`/etc/systemd/system`.

**What happened:**
- **Online installer**: confirmed dead. The URL answers "Omarchy installs from its ISO now".
- **`airootfs.sfs` is the wrong image.** It's the live *installer*: archinstall,
  no Hyprland, uwsm or waybar. The installed system is the ISO's
  `arch/x86_64/omarchy-root.img.zst`: a raw **btrfs** filesystem (label
  `omarchy-root-image`, subvolume `omarchy-root`).
  - `../omarchy/extract.sh` restores it with `btrfs restore -x -m -S` in a throwaway
    container: no loop mount, no host root.
  - Owners, modes and file caps survive. **Setuid bits don't**; the `rootfs` stage
    puts them back from pacman's mtree files.
- **Plain `pacman -Syu` breaks**:
  - The image has no `[omarchy]` repo, and its mirrorlist is all commented out.
  - Arch's live mirrors then want a newer Hyprland than Omarchy pins
    (`omarchy-hyprland-titlebars` needs `hyprland=<exact>`).
  - The fix is Omarchy's own "stable" config: `pacman-stable.conf` +
    `mirrorlist-stable` (a dated Arch snapshot).
  - Omarchy's pacman hook also refuses direct upgrades without
    `OMARCHY_ALLOW_DIRECT_PACMAN=1`.
- **The user**: no `wheel`/sudo. The repo's rule is no root for the user. It's created
  with the builder's UID for `keep-id`.

## 2. Running it

**Suggested (both):**
- **Host setup**: rootless podman with subuids, plus `loginctl enable-linger`.
- **Run**: `podman run -d --systemd=always --userns=keep-id -p 5900:5900` with
  `WLR_BACKENDS=headless AQ_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1
  LIBGL_ALWAYS_SOFTWARE=1`, `CMD ["/sbin/init"]`.
- **Start**: `podman exec` as the user to run `Hyprland &`, `sleep 3`,
  `WAYLAND_DISPLAY=wayland-1 wayvnc 0.0.0.0 5900`.
- **GPU**: `--device /dev/dri --group-add keep-groups` and drop `LIBGL_ALWAYS_SOFTWARE`
  for hardware rendering.

**What happened:**
- **No systemd** (the repo's design). `--init` runs `omarchy-session` as CMD, which:
  - starts Hyprland and waits for its socket (no `sleep 3`), then wayvnc and
    websockify/noVNC;
  - exits when any of them does, so the container stops.
- **Pure headless + llvmpipe** was not the path taken. Hyprland got a DRM device: the
  host's **vkms** card, with `LIBSEAT_BACKEND=noop` (no logind/seatd), and Mesa renders on
  the CPU.
  - Careful: `card0` was the NVIDIA GPU; vkms was `card2`. `o_run` now picks the vkms card
    and refuses real GPUs.
  - One compositor per vkms card.
- **`--device /dev/dri` (all of it) is too broad.** It hands over the host's real display
  cards. Pass one render node instead: see `intel-igpu-render-node.md` for the Intel
  iGPU's `renderD128`, which needs no SR-IOV for containers.
- **wayvnc**:
  - needs `-o <output>`;
  - needs `-r` (render cursor), or the pointer is invisible.
- **Omarchy's session expects systemd/uwsm** (`uwsm-app`, `systemd-run`, `systemd-cat`,
  `uwsm stop`, `systemctl poweroff`). Shims in `/usr/local/bin` stand in for them.
- **Lock screen**: its PAM service (`omarchy-lock-password`) is normally written by the
  installer; without it no unlock is possible. The image ships a `pam_permit` one.
- **Port 5900 → 7100+N** (and noVNC 6280+N), so instances don't collide.
- **Linger**: not needed here (the user runs the containers from a session or a host
  instance).

## 3. Caveats from the notes, checked

| Note | Outcome |
|---|---|
| Installer may need a TTY / Docker daemon | moot: ISO only, and no installer run at all (the rootfs is already installed) |
| Live ISO autologin / first-boot hooks | moot for `omarchy-root.img` (no units run without systemd); `omarchy-provision-first-run` runs harmlessly at session start |
| GPU passthrough via `/dev/dri` | refined: one render node or a vkms card, never the whole directory |
| Quadlet for autostart | not done |
