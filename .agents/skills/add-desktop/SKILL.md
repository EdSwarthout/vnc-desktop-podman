---
name: add-desktop
description: >-
  Checklist and procedure for adding a new Linux desktop environment (e.g. xfce, lxqt,
  gnome, kde, mate, cinnamon, openbox) or adding a new distro stage to an existing desktop
  in vnc-desktop-podman. Use when adding or modifying desktop Containerfiles, sessions,
  panel defaults, screen-lock prevention, or desktop gallery screenshots.
---

# Adding a Distro Desktop

Desktops are Layer 2 images built on a distro's `browser` stage
(`BASE=localhost/vnc-desktop-<distro>:browser[-<version>]`).

## Procedure

1. **Create or extend `container/<desktop>/Containerfile`:**
   - New directory: start with `ARG BASE=localhost/vnc-desktop-<distro>:browser[-<version>]`
     and a header comment listing stages (follow `container/xfce/Containerfile`).
   - Add stage `FROM ${BASE} AS <distro>`, `USER root`, and declare unused
     `ARG USERID`, `ARG USER_UID`, `ARG USER_GID` (prevents unconsumed build-arg warnings).
   - Add one **sorted** package install `RUN` with that distro's cache cleanup tail:
     - Ubuntu/Debian: `apt-get update && apt-get install -y --no-install-recommends ... && { mountpoint -q /var/cache/apt-<distro> || apt-get clean; } && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin`
     - Fedora: `dnf -y install ... && { mountpoint -q /var/cache/apt-fedora || dnf clean all; }`
     - Arch: `pacman -Syu --noconfirm --needed ... && { mountpoint -q /var/cache/apt-archlinux || rm -rf /var/cache/apt-archlinux/*; } && rm -rf /var/lib/pacman/sync/*`
   - Write `/usr/local/bin/vnc-session` (replaces `vnc`'s xterm session; inherits `+x`).
   - End with `USER ${USERID}`.

2. **Prototype in a throwaway nested instance first:**
   - Verify an X11 session exists (Wayland-only sessions like GNOME Shell 50 cannot run on
     TigerVNC).
   - Check whether the session manager requires systemd/logind; if so, start components
     directly (as in Ubuntu's `gnome`) or run a stand-in per-user system D-Bus (as in
     Debian's `gnome`).
   - Test package lists interactively via `podman exec -u root` before editing the
     Containerfile.

3. **Verify initial appearance on a fresh home:**
   - Run `tests/screenshot.sh` on a brand-new home and inspect the PNG.
   - Distros without recommends/weak deps often break default panel layouts (missing
     applets, "Error" boxes, blank icons, volume red-X). Fix with:
     - GSettings override in `/usr/share/glib-2.0/schemas/99_vnc-desktop.gschema.override`
       followed by `glib-compile-schemas --strict /usr/share/glib-2.0/schemas`, or
     - Config override in `/etc/xdg/...` (pair any `sed` edit with a `grep -q` assertion).

4. **Ensure screen locking is impossible:**
   - The container user has no password to unlock a locked screen.
   - Omit screen-locker packages where possible (and assert `! command -v <locker>` at
     build time), or disable via kiosk/gsettings + removing D-Bus activation / session
     components.
   - Add the desktop's lock command and D-Bus name to `tests/lock.sh` if not already there.
   - Run `d_test` (which runs `tests/lock.sh` with `d_exec -s`) and verify 0 failures.

5. **Verify log out stops the container:**
   - Logging out from the desktop must end `/usr/local/bin/vnc-session` so `vncserver` and
     the container exit cleanly, and `podman start` brings it back.
   - If the desktop's built-in Log Out requires systemd/gnome-session, add a menu entry
     (like `vnc-logout.desktop` in `container/gnome/Containerfile`) and document it.

6. **Screenshot support:**
   - Include a CLI screenshot tool that saves directly to a path without an interactive
     dialog (`scrot` if the desktop's own tool can't).
   - Add a branch for it in `tests/screenshot.sh` if needed.

7. **Wire into `env.rc` and `.containerignore`:**
   - Add the target to `d_targets_<distro>`, update the `d_target` comment, and add its
     description to `d_descs` (keyed `<target>` or `<distro>:<target>`).
   - If the Containerfile `COPY`s any new repo files, add a `!` line in `.containerignore`.

8. **Update documentation and gallery:**
   - `README.md`: intro table, file table, Images table, Desktops section, `d_all` list.
   - `AGENTS.md`: intro, Repository layout, Design decisions (Desktop specifics).
   - Capture fresh-home screenshot: `[d_distro=<distro>] d_screenshots N <desktop>` and add
     a section in `docs/README.md`.

## Validation
- `shellcheck` passes on all scripts and `bash tests/test_env.sh` passes.
- `[d_distro=<distro>] d_test N <desktop>` passes all checks (`0 failed`), and the
  captured PNG in `/tmp/d_test/` looks clean.
