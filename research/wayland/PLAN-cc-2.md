# Wayland desktops: review of research-20261117 and plan (Claude Code)

Status: planned, 2026-11-26. Builds on this branch (research/wayland, with deb/, vnc-pkg,
AGENTS.md); input: origin/research-20261117 (3307cbf) and ./PLAN.md. Revision 2 of
./PLAN-cc.md, with PLAN.md's strong points folded in (comparison: ./PLAN-compare.md).
Supersedes ./PLAN.md where they differ.

## 1. Review of `research-20261117`

**Proven, and worth keeping**
- `gnome-shell --headless --wayland` (Shell 50.1) runs without systemd on amd64 (hwd23)
  and arm64 (DGX Spark), with no `/dev/dri`, no root and no host setup. It needs a private
  system bus (`system-bus.conf`) and `mock-logind.py` for a clean start ("Failed to start
  state machine" without it). Any number of instances can run at once.
- An Intel render node passed in is used with no script change (gbm renderer, iris). The
  NVIDIA node on the Spark is untried (it needs CDI).
- gnome-remote-desktop works both ways: mirroring the Shell's monitor (`rdp.sh`,
  credentials in the keyring) and headless (`rdp-headless.sh`, a monitor per client,
  `credentials.ini`). Chrome works with `--ozone-platform=wayland`, and mouse input works.
- The workarounds are written down: `grdctl … enable` needs systemd, so set the gsettings
  keys instead. Set credentials before the daemon starts (`SEC_E_MESSAGE_ALTERED`).
  The FUSE clipboard aborts the daemon, so connect with `-clipboard`.

**Drop**
- KMS on vkms (`kms.sh`, `fake-run.sh`): it works on both machines but brings nothing.
  It needs a host `modprobe`, root `/run` fakes, 1024x768, one instance per card, and
  still renders on the CPU. ./PLAN.md says the same.

**Problems in the prototypes, to fix when integrating**
- They hard-code `/home/ed/shell` and uid 1001, including the `<listen>` path in
  `system-bus.conf`. The password sits in a plaintext `rdp-pass`, and packages were
  installed by hand as root, not in a Containerfile. Image names are the old `u2604cc:*`.
- Only bare `gnome-shell` ran: no gnome-settings-daemon, no Xwayland. Lock and Log Out are
  untested. There's no screenshot route (`gnome-screenshot` hangs, Shell.Screenshot is
  "not allowed"), and no browser access.
- Omarchy: it works, but it's standalone (`o_*`), amd64 only, a 7.5 GB rootfs from the
  ISO, with two aquamarine 0.15.1 workarounds, and its lock screen accepts any character.
  Out of scope here: leave it on `research-20261117`.

**Gaps in ./PLAN.md that this plan closes**
- It names the target `gnome-wayland`. `env.rc` reads every `X-Y` target as desktop
  `X` + agent `Y` (`_d_distro`: `_d_layer=${d_target##*-}`), so it would look for
  `container/wayland/`. Target names here have no hyphen.
- It never decides how GNOME fits the noVNC workflow, or which grd mode to use (headless
  gives the bridge and an RDP client separate monitors).
- The test and session helpers only know X: `start.sh` always runs `vncserver`,
  `_d_session_sh` looks for vncserver's child, `_d_wait_ready` and `lock.sh` use
  `xdotool`, and `d_exec -s` passes no `WAYLAND_DISPLAY`/`DISPLAY`.
- GNOME 50's `gnome-session` probably needs systemd (Debian's 48 still had a fallback). To
  be checked, not assumed.
- wayvnc has no classic VncAuth: its auth is RSA-AES or TLS with a user name and password.
- Its labwc websockify points at `127.0.0.1:5900`, but `start.sh` uses 5901. Here it
  stays 5901.
- Its GNOME session ends when the RDP daemon exits, so a client with the clipboard on
  (grd's FUSE abort) would stop the container. Here grd is restarted, and the session
  ends only with gnome-shell.
- "Branched from `main` at `eed45b9`": `eed45b9` is this branch's own AGENTS.md commit.
  The base on main is `eb0f1f3`.

## 2. Design

Two Ubuntu 26.04 desktops on `browser`, amd64 + arm64, CPU rendering. GPU opt-in isn't
part of this plan. A Mesa render node added to `d_run_opts` by hand (`--device
/dev/dri/renderDNNN --group-add keep-groups`) is used by mutter with no change, but only
on the right host and node. Never hard-code `renderD128`, and never pass `card*` or all of
`/dev/dri`:

| Host | Arch | Render nodes | Use |
|---|---|---|---|
| hwd23 | amd64 | `renderD128` Intel UHD 770 (Mesa iris), `renderD129` NVIDIA RTX 4090 | CPU, or `renderD128` only. Never `card1` (drives the host's monitors) or `renderD129` |
| DGX Spark | arm64 | `renderD128` NVIDIA GB10 (no Mesa driver) | CPU only. NVIDIA CDI is a separate, untried investigation |
| Debian 13 / no vkms (hwd4) | amd64 | none needed | CPU (headless needs no `/dev/dri`) |

The desktops:

| | `gnomewl` (GNOME Shell 50, Wayland) | `labwc` (wlroots, Wayland) |
|---|---|---|
| Directory | `container/gnomewl/Containerfile`, stage `ubuntu` | `container/labwc/Containerfile`, stage `ubuntu` (Fedora/Arch later) |
| Compositor | `gnome-shell --headless --virtual-monitor $VNC_RESOLUTION`, private system bus + mock logind | `labwc` with `WLR_BACKENDS=headless`, `WLR_RENDERER=pixman` (or gles2 on llvmpipe, whichever works) |
| Remote | **Bridge**: Xvnc `:1` as today, and `vnc-session` runs a full-screen `xfreerdp3` to grd on 127.0.0.1:3389. Optional published RDP: `d_rdp=1` → `-p 7450+N:3389` | `wayvnc` on 5901 in place of Xvnc, same websockify/noVNC on 6080 |
| Ports | Ubuntu's 6900+N / 6080+N; RDP 7450+N only with `d_rdp=1` | Ubuntu's 6900+N / 6080+N |
| Screenshot | `scrot` on `:1` (the bridge shows the Shell) | `grim` |

**gnomewl session** (`/usr/local/bin/vnc-session`, started by xstartup under `dbus-launch`
as usual, so `start.sh` doesn't change for it):
1. Private system bus at `$XDG_RUNTIME_DIR/system_bus_socket`, config generated or with
   `--address` only, no hard-coded uid. `mock-logind.py` goes to
   `/usr/local/libexec/vnc-desktop/`.
2. Without `DISPLAY`: `gnome-shell --headless --wayland --virtual-monitor
   ${VNC_RESOLUTION:-1440x900}` (Xwayland on, i.e. no `--no-x11`), on the session bus
   from `dbus-launch`. Then whatever gsd-* daemons Phase 1 shows are needed.
3. `pipewire`, `wireplumber`, `gnome-remote-desktop-daemon` in **mirror mode** (rdp.sh
   style): the bridge and any RDP client see the same screen, like VNC `-Shared`. It
   needs the passwordless default keyring: reuse the writer from `container/claude/`
   (`Default_keyring.keyring` + `default`, only when missing). TLS cert generated once
   into `~/.config/vnc-desktop/rdp-tls.{crt,key}`.
4. **RDP password**: `start.sh`'s first-boot passwd block also writes
   `~/.config/vnc-desktop/rdp-pass` (600) from `passwd.init`, so it's the VNC password,
   and only when the image has `gnome-remote-desktop`. If there's no `passwd.init`
   (nested: a copy of the parent's `passwd`), it writes a random one. `vnc-session`
   sets it with `grdctl rdp set-credentials "$USER"` before the daemon starts, and
   `xfreerdp3` reads it with `/from-stdin`, never on a command line. Nothing in the
   container env.
5. Foreground: a loop that runs `xfreerdp3 /v:127.0.0.1 /u:$USER /f -clipboard
   /cert:ignore /auto-reconnect` while gnome-shell is alive (grd is restarted if it
   dies). When gnome-shell exits (Log Out), the loop ends, `vnc-session` kills the rest
   and exits, `vncserver` exits, and the container stops as with every desktop.
6. It exports `WAYLAND_DISPLAY`, Xwayland's `DISPLAY` and `DBUS_SYSTEM_BUS_ADDRESS` in its
   own environment, so `d_exec -s` apps open on the Shell, not behind the bridge on `:1`.
7. gsettings override (`99_vnc-desktop.gschema.override`): lock off, `disable-lock-screen`,
   `idle-delay=0`, `always-show-log-out`, dash favourites Chrome/Files/Terminal; RDP
   `enable=true`, `view-only=false`.

**labwc session**: start.sh gets one branch: if `/usr/local/bin/vnc-wayland` exists, it
runs that in place of `vncserver :1 -fg …`, with websockify unchanged.
`vnc-wayland` is bash: `dbus-launch`, then `labwc` headless with
`wlr-randr --custom-mode $VNC_RESOLUTION`, then `wayvnc -r` on 0.0.0.0:5901. It exits when
labwc or wayvnc does, which is the same contract as `vncserver-wrapper`. Its child that
isn't `wayvnc` is the session. wayvnc's config and RSA key are made in
`~/.config/wayvnc/` from `passwd.init` at first boot (user `$USER`). The TigerVNC
`passwd` is still written, for `_d_wait_ready` and `d_vnc`.
Packages: `labwc wayvnc wlr-randr grim wtype foot xwayland swaybg`. A `menu.xml` with
Terminal, Chrome, Exit (Exit ends labwc, so the container stops).
Why labwc and not sway: Arch's sway carries `cap_sys_nice=ep`, a file cap that breaks
under nested podman, and labwc was already proven headless on a render node for Omarchy.
aquamarine needs `xdg_wm_base` v6, which sway 1.12 doesn't offer.

**env.rc / tests** (in this branch's style: shellcheck clean, cases in `tests/test_env.sh`):
- `d_targets_ubuntu += gnomewl labwc`, plus `d_descs`.
- `d_rdp_ports0=([gnomewl]=7450)`: `d_run` adds `-p ${bind}$((7450+N)):3389` when
  `d_rdp=1` and the target has an entry (it respects `d_bind`). `d_rdp` runs `xfreerdp3`
  (or prints the line) with the password from `$d_home/.config/vnc-desktop/rdp-pass`.
  7450–7499 is free (7250/7300 were grok's and t3code's).
- `_d_session_sh`: also match `/bin/bash /usr/local/bin/vnc-wayland`, and skip `wayvnc`
  as well as `Xtigervnc|Xvnc`.
- `d_exec -s`: add `WAYLAND_DISPLAY` and `DISPLAY` to the environment it copies.
- `_d_wait_ready`: on labwc, `grim` succeeds, in place of the `xdotool` window check.
  gnomewl keeps `xdotool` (the bridge window on `:1` appears only after RDP connects).
- `tests/screenshot.sh`: a `grim` branch when `WAYLAND_DISPLAY` is set and there's no X
  screenshot tool.
- `tests/lock.sh`: Wayland branches. gnomewl: send `org.gnome.ScreenSaver.Lock` (session
  bus) and Super+L (`xdotool` into the bridge, which RDP forwards), then FAIL if
  `org.gnome.ScreenSaver.GetActive` is true, or if a `wtype`/`xdotool` text test into a
  Shell-side terminal doesn't arrive. labwc: no locker is installed. Check that no
  `ext-session-lock` client exists, and type with `wtype` into foot.
- `d_test`'s `session_end` matches `vncserver exited` *or* the labwc wrapper's message
  (`start.sh` names `vnc-wayland`).

## 3. Phases

**Phase 1: answer the open questions in throwaway nested instances** (results go into
this file; nothing is wired up yet). On a nested `vnc-desktop-ubuntu:gnome-2604`
instance, with packages added as root (`gnome-shell gnome-remote-desktop pipewire
wireplumber xwayland python3-dbus python3-gi openssl freerdp3-x11 gnome-settings-daemon
gnome-terminal nautilus`):
1. Shell with Xwayland: does it start? Which DISPLAY does it pick (`:1` is Xvnc's)? Do an
   X client and Chrome (both ozone modes) work? Do the Electron agent apps (Antigravity,
   OpenCode Desktop) work, over Xwayland and with `--ozone-platform-hint=auto`? They're the
   reason Xwayland matters. Claude Desktop stays `gnome`-only.
2. `gnome-session` without systemd: does it work at all? If not, which `gsd-*` daemons
   are needed for themes, keyboard and xsettings?
3. Is the mock logind needed, or does an empty bus do? (Keep the mock if in doubt.)
4. Bridge: full-screen `xfreerdp3 /from-stdin` on Xvnc `:1` against mirror-mode grd, then
   noVNC in Chrome. Check input including Super, the overview and the keyboard layout.
   Check Super+Space and the overview key through both viewers in a row (noVNC/VNC, then
   RDP): the Omarchy notes show Super+Space getting lost through nested viewers. With a
   second, external RDP client at the same time, does it mirror?
5. Clipboard: aim for a server-side fix, so that external clients with the clipboard on
   don't crash grd. Look for a grd setting that turns off clipboard redirection, and check
   whether `fusermount3` works in a top-level instance (`d_run` passes `/dev/fuse`; nested,
   it failed). The bridge's `-clipboard` and the grd restart are only the fallback.
6. Lock (`org.gnome.ScreenSaver.Lock`, Super+L) and Log Out → does gnome-shell exit?
7. Resource use per instance (Shell + grd + pipewire + Xvnc + bridge): RSS, CPU while idle
   and while in use, and `pids.current` against `pids.max` (KDE alone is ~550 threads).
8. labwc: headless pixman and gles2 with no `/dev/dri`; wayvnc RSA-AES auth from noVNC and
   from TigerVNC `vncviewer`; `wlr-randr` sets the size; grim, wtype, Xwayland, Chrome.
9. arm64: do `labwc`, `wayvnc`, `wlr-randr`, `grim` and `wtype` exist in Ubuntu 26.04
   arm64 (only freerdp3 and the GNOME packages are proven there)? Use `apt-cache policy` in
   a `vnc-desktop-ubuntu:browser-2604` container on the DGX Spark.
10. Optional: does labwc with pixman and no `/dev/dri` work on Debian 13 and Fedora 45 too
    (packages exist?), as a zero-GPU baseline for later stages.

**Phase 2: `labwc`** (the smaller change, and it proves the Wayland branch in start.sh
and the helpers): Containerfile, `vnc-wayland`, the start.sh branch, the env.rc/tests
changes above, `.containerignore` lines for new COPY sources. `d_test 1 labwc` passes all
checks. By hand: `vnc-pkg install`/`remove` of a small package works and `sudo -n true`
is still refused.

**Phase 3: `gnomewl`**: Containerfile (sorted package `RUN` with the apt cache tail,
`mock-logind.py`, `vnc-session`, the gschema override with `glib-compile-schemas
--strict`, keyring writer), the rdp-pass step in start.sh, `d_rdp`/`d_rdp_ports0`, and the
lock.sh branch. `d_test 1 gnomewl` passes; checked by hand: `d_rdp=1` plus an external
`xfreerdp3`, no password in `podman inspect`, process environments or command lines, and
`vnc-pkg` working. Tested on amd64 and on the DGX Spark (arm64). Optionally on hwd23 with
`renderD128` by hand (two instances, `drm-engine-render` time in fdinfo, host desktop
unaffected).

**Phase 4: docs**: README (tables, the Wayland desktops, `d_rdp`), AGENTS.md (layout,
design decisions: gnomewl bridge and RDP password, labwc wayvnc auth, ports 7450+N),
`.agents/skills/add-desktop` (Wayland notes: no hyphen in names, lock check),
`docs/ubuntu/{gnomewl,labwc}.png` with `d_screenshots`.

**Later, not in this plan**: labwc stages for Fedora/Arch; agent desktops on gnomewl
(`gnomewl-opencode` etc. work by name with no env.rc change; `claude` stays
`gnome`-only); GPU render-node opt-in; Omarchy.

## 4. Risks
- GNOME 50 headless without gnome-session may lack pieces (settings, portals): Phase 1
  decides how far gnomewl goes.
- The bridge encodes twice (RDP then VNC), all inside the container: it costs CPU, not
  bandwidth.
- wayvnc's user-name login differs from today's password-only VncAuth.
- grd in mirror mode needs the keyring. The plaintext keyring and `rdp-pass` match the
  existing "no user password" choice, and they're plaintext-equivalent to the TigerVNC
  `passwd` file.

## 5. Resuming
> Start Phase 1 of research/wayland/PLAN-cc-2.md in throwaway nested Ubuntu instances and
> record the results there.

