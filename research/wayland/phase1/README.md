# Phase 1 of PLAN-cc-2.md: results

Status: **done**, 2026-11-26, on hwd23 (amd64) in nested instances inside cc20u (Ubuntu
26.04 images built from this branch). The two instances were left running for a look:
`cc20u_vnc-desktop-ubuntu-gnome-2604-6901` (gnomewl prototype) and
`cc20u_vnc-desktop-ubuntu-browser-2604-6902` (labwc prototype). CPU rendering only: no
`/dev/dri` in either. Not run on the DGX Spark, and not in a top-level (host) instance.

## Files

| File | What |
|---|---|
| `gnomewl-session` | prototype of gnomewl's `vnc-session`: private system bus, mock logind, mock session manager, keyring, `gnome-shell --headless` with Xwayland, 11 `gsd-*` plugins, pipewire, wireplumber, grd in mirror mode (restarted if it dies), and the full-screen `xfreerdp3` bridge on Xvnc `:1` while the Shell lives |
| `mock-logind.py` | from `research-20261117` (`wayland/`), unchanged |
| `mock-session-manager.py` | **new**: `org.gnome.SessionManager` stand-in. Log Out / Power Off open the Shell's own end-session dialog. On confirm it sends SIGTERM to gnome-shell, which ends the session and stops the container |
| `env.sh` | `. env.sh` in the instance: a client of the prototype's Shell (buses, `WAYLAND_DISPLAY`, Xwayland `DISPLAY` and `XAUTHORITY`) |
| `setup.sh` | on the parent: installs the test packages as root in a nested `gnome` instance, copies this directory to `~/phase1`, and points its `xstartup` at `gnomewl-session` |
| `labwc-session` | prototype of labwc's `vnc-wayland`: labwc headless + wayvnc (port 5911 here, beside the instance's Xvnc), ends when either does |
| `*.png` | screenshots below |

## gnomewl: GNOME Shell 50 over the RDP-in-VNC bridge

| Question (PLAN-cc-2 Phase 1) | Answer |
|---|---|
| 1. Shell with Xwayland | **Works.** Xwayland is `:0` (Xvnc has `:1`; mutter also opens `X2`, `GNOME_SETUP_DISPLAY`). X clients need mutter's cookie: `XAUTHORITY=$XDG_RUNTIME_DIR/.mutter-Xwaylandauth.*`. Without it: "Missing X server". Chrome works with `--ozone-platform=wayland` and `=x11`. **OpenCode Desktop** (2.4.2) works as a native Wayland client by default (Electron picks Wayland itself) and with `--ozone-platform=x11` (`gnomewl-opencode.png`). Antigravity not tried (also Electron) |
| 2. gnome-session | **Needs systemd** in GNOME 50: it only starts `gnome-session@gnome.target` ("Failed to start unit … org.freedesktop.systemd1 does not exist"), with no builtin fallback. All 16 `gsd-*` plugins run when started directly. The prototype starts 11 (a11y-settings color datetime housekeeping keyboard media-keys power screensaver-proxy sharing sound xsettings). They log harmless warnings (no UPower, no accountsservice) |
| 3. Mock logind needed? | **No, but keep it.** Without it: "Could not get a proxy for user … login1", "Failed to start state machine", but the Shell, the bridge and Log Out all work |
| 4. Bridge | **Works** (`gnomewl-bridge-overview.png`, `gnomewl-apps.png`): the Shell at 1440x900 on Xvnc `:1`, so noVNC, `d_vnc`, `scrot` and XTEST input work unchanged. Clicks and keys go through, and so does Super (opens the overview). Super+Space through a real browser/noVNC was **not** tested (only XTEST into the bridge). A second RDP client mirrors the same screen |
| 5. Clipboard | **Crashes grd** with a client that has the clipboard on: `fusermount3: mount failed: Permission denied`, then `[FUSE Clipboard] Failed to mount FUSE filesystem` (`g_error`, abort). `fusermount3` is setuid root, but container root has no `CAP_SYS_ADMIN`, so a top-level instance probably fails the same way (not tested). grd has no setting for it: the schema has no clipboard key, and the binary has no environment switch. The restart loop brings grd and the bridge back in about 2 s (every client is dropped). `freerdp-proxy3` with `[Channels] Clipboard=false` in front of grd does drop the client's `cliprdr` channel (grd didn't crash), but its own NLA connection to grd stalled: open |
| 6. Lock, Log Out | **Lock is impossible:** `org.gnome.ScreenSaver.Lock` and `GetActive` fail with "org.gnome.Shell.ScreenShield was not provided" (no GDM, no shield), Super+L does nothing (also with gsd-media-keys running), and `org.freedesktop.ScreenSaver.Lock` is "not supported". **Log Out**: without gnome-session the menu entry did nothing ("org.gnome.SessionManager was not provided"). With `mock-session-manager.py` it opens the Shell's dialog (`gnomewl-logout-dialog.png`). Confirming it ended gnome-shell, the session, and the container ("vncserver exited"); Cancel keeps it. `podman start` brought it back |
| 7. Resources | Idle (Shell, gsd, grd, pipewire, Xvnc, bridge, websockify): **~1.2 GB RSS, 300-370 threads**, ~0% CPU. Moving the pointer for 10 s: ~15% of one core in total |
| 9. arm64 packages | All present in Ubuntu 26.04 arm64 (ports): labwc, wayvnc, wlr-randr, grim, wtype, foot, xwayland, swaybg, freerdp3-x11, freerdp3-proxy, gnome-remote-desktop, gnome-shell, scrot. Checked from amd64 with arm64 indexes, not run on the Spark |

**Gotchas found (now handled in `gnomewl-session`):**
- **`USER` isn't set** in a podman container: `grdctl rdp set-credentials "$USER"` stored an
  empty user name (`grdctl status`: "Username: (empty)"), and xfreerdp3 then prompted for the
  domain and gave up (`ERRCONNECT_CONNECT_CANCELLED`). Fixed with `USER=${USER:-$(id -un)}`.
- `dbus-daemon` wants a `<listen>` in the config file even with `--address`: the config is
  generated with the socket path.
- **Password off the command line**: `xfreerdp3 /args-from:stdin` (one argument per line,
  `/p:…` included) works. `/from-stdin` prompts for the domain first. The prototype also
  passes an empty `/d:`.
- `gnome-screenshot` with the session bus set hangs (Shell's screenshot interface). Without
  it, it falls back to X11 on `:1`. `scrot` on `:1` is reliable: gnomewl needs `scrot`.
- D-Bus-activated apps inherit `DISPLAY=:1` from `dbus-launch`.
  `dbus-update-activation-environment` sets `WAYLAND_DISPLAY`, Xwayland's `DISPLAY` and
  `XAUTHORITY` once the Shell is up.
- `grdctl rdp set-tls-cert` prints "BIO_new failed for certificate" / "RDP server
  certificate is invalid", but TLS works (also seen on the Spark before).
- `pkill -f PATTERN` from `podman exec sh -c '…'` kills that shell if the line contains the
  pattern (exit 143): use a bracket (`'[g]nome-screensho'`) in a separate exec.

## labwc + wayvnc

| Question | Answer |
|---|---|
| 8. Renderer without `/dev/dri` | **pixman only**: gles2 fails ("Cannot create GLES2 renderer: no DRM FD available"). pixman at 1280x800 is fine for a terminal and Chrome |
| wayvnc auth | With `enable_auth=true`, `username`, `password`, `rsa_private_key_file` (PEM: `openssl genrsa -traditional`) and `relax_encryption=true`, wayvnc 0.9.1 offers RA2_256 (129), RA2 (5) and Apple DH (30). **No VncAuth (2).** **TigerVNC 1.15**: RA2_256 with a user name and password (works from `VNC_USERNAME`/`VNC_PASSWORD` in the viewer's environment), after a trust-on-first-use "Server key fingerprint" dialog. A wrong password is refused ("Invalid username or password"). **noVNC 1.6** (its types: 1, 2, 6, 16, 19, 22, 30, 113, 129-as-UnixLogon): asks for user name and password and logs in (`labwc-novnc-auth.png`) |
| Size | `wlr-randr --output HEADLESS-1 --custom-mode WxH` works |
| Tools | `grim` (screenshot) and `wtype` (typing) work. Typing through the VNC viewer (XTEST into TigerVNC on `:1`) reaches foot |
| Apps | Chrome `--ozone-platform=wayland`; Xwayland is started on demand on `:0` (no cookie needed); xterm on it (`labwc-apps.png`) |
| End of session | `labwc --exit` needs `LABWC_PID` (set only in labwc's children): `LABWC_PID=$(pgrep -o -x labwc) labwc --exit`. labwc exits, the script kills wayvnc and ends |
| 10. Debian 13 / Fedora 45 | Packaged on both: Debian labwc 0.8.3, wayvnc 0.9.1, wlr-randr, grim, wtype, foot, xwayland. Fedora labwc 0.20.2, wayvnc 0.9.1, wlr-randr 0.5.0, grim 1.5.0, wtype, foot, Xwayland 24.1.15 |

## Changes to PLAN-cc-2.md's design

1. gnomewl gets **`mock-session-manager.py`** (or the same in the session script) for Log
   Out / Power Off. Without it, Log Out does nothing.
2. gnomewl starts the **`gsd-*` plugins** itself. gnome-session is out (systemd only).
3. gnomewl's session exports **`USER`** and **`XAUTHORITY`** and updates the bus activation
   environment. `d_exec -s` must also copy `XAUTHORITY` (beside `WAYLAND_DISPLAY`,
   `DISPLAY`).
4. The bridge passes the password with **`/args-from:stdin`**.
5. gnomewl installs **`scrot`**, not `gnome-screenshot` (so `tests/screenshot.sh` picks
   scrot on `:1`).
6. **lock.sh** for gnomewl: "ScreenShield was not provided" means no lock is possible; Super+L
   through the bridge must leave the screen unchanged.
7. **Clipboard**: keep the grd restart loop. External clients must turn the clipboard off
   (`-clipboard`) until there's a server-side fix: the freerdp-proxy3 filter, if its NLA to
   grd can be made to work, or a grd built without the FUSE clipboard. Document it for
   `d_rdp`.
8. **labwc**: pixman only without a GPU. **Auth is user name + password** (RA2 for TigerVNC
   1.15, ARD for noVNC 1.6), so `d_vnc` needs `VNC_USERNAME`/`VNC_PASSWORD` for the viewer
   (only in the host-side viewer process) instead of `-passwd FILE`. Older TigerVNC
   viewers without RA2 can't connect. The session's exit uses `LABWC_PID`.

## Not tested yet

- Super+Space and other chords through a real browser on noVNC (needs a person, or the
  host's viewer), and an RDP client from outside the instance (`d_rdp=1`).
- The DGX Spark (arm64) runs, and a top-level (non-nested) instance (FUSE clipboard with
  `/dev/fuse` at the top level).
- Antigravity over Xwayland; keyboard layouts (gsd-keyboard + RDP keymap); window
  decorations of X apps with `mutter-x11-frames` (they render).
- The freerdp-proxy3 clipboard filter end to end.
