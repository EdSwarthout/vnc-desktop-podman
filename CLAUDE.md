# CLAUDE.md — vnc-desktop-podman

Rootless-podman image: Ubuntu 26.04 + XFCE, LXQt, GNOME Flashback, KDE Plasma, MATE or Cinnamon,
or Debian 13 (trixie) + GNOME Shell, over TigerVNC/noVNC, with
Chrome, Claude Code and nested podman (plus smaller headless/xterm stages).
See `README.md` for user-facing setup.

## Files
- `ubuntu/Containerfile` — stages `base` (headless + nested rootless podman) →
  `vnc` (TigerVNC/noVNC, xterm session) → `chrome` → `xfce` / `lxqt` / `gnome` / `kde` / `mate` / `cinnamon`.
  `d_target` in `env.rc` picks one (default `xfce`); images are tagged
  `u2604cc:<stage>`. Package lists are kept **sorted**.
- `debian/Containerfile` — Debian trixie: `base` → `vnc` → `chrome` → `gnome`
  (GNOME Shell), tagged `d13cc:<stage>`. Its `base`/`vnc`/`chrome` follow
  Ubuntu's nearly line for line: **change both** when changing those stages.
  `d_distro` (`ubuntu` default | `debian`) in `env.rc` picks the directory. The build
  context is the repo root for both, so they `COPY` the shared `start.sh` and
  `nested-subids`; anything distro-specific goes in that distro's directory.
- `start.sh` — entrypoint (PID 1's child under `--init`), shared by all stages:
  first-boot seeding of the home volume and `nested-subids`; then, if the
  stage has `vncserver`, runs `vncserver -fg` and `websockify` and exits when
  either does, so the container stops; otherwise (`base`) `exec sleep infinity`.
- `nested-subids` — `/usr/local/sbin`; `start.sh` runs it via `sudo` at every
  boot to fit subids and `newuidmap` caps to the container.
- `env.rc` — host-side bash helpers, `source`d from any cwd; defaults at the top,
  then `.env` (may override `d_dir`, `d_user`, `d_distro`, `d_target`, …), then derived values;
  per-distro settings (`d_bases`, `d_images`, `d_targets_<distro>`, apt cache)
  are resolved at call time by `_d_distro`, so `d_distro=debian d_build` works,
  and `d_build`/`d_run` refuse a `d_target` that isn't a stage of that distro: `d_0`, `d_build`,
  `d_build_fresh`, `d_select N`, `d_run_new`, `d_run`, `d_vnc`, `d_novnc`, `d_logs`,
  `d_all N [STAGE...]` (build + run every stage on instances N, N+1, …, then
  `eval "$d_all_cmd"` in the background per instance, default `d_vnc`), `d_screenshots N [STAGE...]` (retake
  `docs/<distro>/<stage>.png` on a throwaway instance N).
- `tests/tests.sh` — nested-podman checks, run inside an instance.
   `tests/screenshot.sh` — full-screen PNG of `:1` via `xfce4-screenshooter` / `screengrab` / `gnome-screenshot` / `spectacle` / `scrot` (xfce, lxqt, gnome, kde, mate + cinnamon); copy it out
  with `podman cp` and look at it to check a desktop by script.
- `docs/` — `README.md` gallery with one screenshot per stage of the desktop
  on a fresh home (`ubuntu/<stage>.png`, `debian/<stage>.png`); retake a stage's picture when its initial
  look changes (`[d_distro=debian] d_screenshots N <stage>`).
- `.env` — `export VNC_PASSWORD=…` and local settings such as `d_dir=…`
  (gitignored, never commit or print it). Usually absent inside an instance.

## Where you're probably running
Claude Code usually runs *inside* an instance (e.g. `cc1u`) with this repo on
the home volume. Every stage has a nested rootless podman
for scratch containers, but it is *not* the host's podman, and the host paths
(`$d_dir`, the NFS apt cache) are not visible. When `$container` is set, `env.rc`
switches to nested paths (`d_dir=~/Containers`, instance N named `<this instance>_N<distro letter>` (e.g. `cc1u_1d`) with home `~/Containers/<that name>`,
the instance's own apt cache mount, no `--hostname`), so `d_build`/`d_run` here
build and run a nested instance in the nested podman, not a host one. Check things in the container directly (`/proc/1/environ`,
`mountpoint /var/cache/apt/archives`, `~/.config/tigervnc`) and test `env.rc`
changes with a stubbed `podman`, both ways (`container=` for host behaviour):
```bash
T=$(mktemp -d)   # d_run really creates the home dir and its passwd.init there
VNC_PASSWORD=x bash -c 'podman(){ echo "[podman $*]"; }; source ./env.rc; d_dir='$T'/n; d_select 1; d_run'
VNC_PASSWORD=x container= bash -c 'podman(){ echo "[podman $*]"; }; source ./env.rc; d_dir='$T'/h; d_select 1; d_run'
```
(Homes, names and ports are worked out at call time, so setting `d_dir` after
sourcing works; add `d_distro=debian` to a command for Debian. `d_run_new` loops
on `podman container exists`, so stub that to fail.)
The user builds, runs and pushes from the host. This clone has an `origin`
(GitHub), but don't push from here: commit locally and leave the push to the user.

## Design decisions (don't undo without asking)
- **Home is a volume** (`$d_dir/u2604ccN` or `$d_dir/d13ccN` → `/home/ed`). Anything put in
  `/home/ed` at build time is hidden; per-user setup belongs in `start.sh`'s
  first-boot blocks (guarded by "file doesn't exist yet") or runs at runtime.
  The user's own files for new homes go in `<distro>/user_files/` (gitignored, may
  be absent; the user's, don't edit or print them): the base stage packs them
  into `/usr/local/share/user_files.tar` (`COPY LICENSE <distro>/user_file[s]`:
  LICENSE is there because COPY fails when nothing matches), and `start.sh`
  unpacks it as the last step of the "no `~/.bashrc`" first-boot block, over
  `/etc/skel`'s files. The `D_NAME` `.bashrc` addition runs only when
  `$D_NAME` is set and the `.bashrc` doesn't mention it yet.
- **Claude Code** is installed by the user at runtime via `install_claude`
  (native installer → `~/.local/bin`, self-updating). Not baked into the image.
- **Shared apt cache**: `$d_dir/apt-cache/archives` for Ubuntu,
  `$d_dir/apt-cache-debian/archives` for Debian (separate: same file names,
  different contents; `d_aptcache` in `.env` forces one; nested, it's the
  instance's own mount whatever the distro), NFS-shared between machines, is mounted on `/var/cache/apt/archives` in both build and
  run. `docker-clean` is replaced by `docker-no-pkgcache`; every apt `RUN` ends
  with `{ mountpoint -q /var/cache/apt/archives || apt-get clean; }` and
  `rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin`. Keep that tail on new
  apt `RUN`s. Not a buildah cache mount, because it must be shareable over NFS.
- **VNC password** never goes in the container env (it stayed in `podman
  inspect` and every desktop process inherited it). While the home has no
  `~/.config/tigervnc/passwd`, `d_run` writes `passwd.init` (600) beside it,
  or nested without `$VNC_PASSWORD` copies this instance's `passwd`;
  `start.sh` converts and deletes it, and unsets a `$VNC_PASSWORD` given by a
  plain `podman run -e`.
- **No root for the user**: no `sudo` group or blanket rule; sudoers allows only
  `/usr/local/sbin/nested-subids ""` (no arguments). So everything needed at
  runtime goes in the `base` package list; don't add steps that need `sudo`.
- **User and UID** are build args (`USERID`, `USER_UID`; `d_build` passes
  `$d_user` and `id -u`), so keep-id lines up for any host user. Scripts use
  `$USERID` / `$SUDO_USER`, not a literal `ed`.
- **Session comes from the image**: each stage with a display installs
  `/usr/local/bin/vnc-session` (xterm / `startxfce4` / `startlxqt` / Flashback's parts / `startplasma-x11` / `mate-session` / `cinnamon-session-cinnamon2d`); the home's
  `xstartup` only runs it under `dbus-launch`, so a home works with any stage.
- **LXQt without recommends** needs explicit `breeze-icon-theme`,
  `libxcb-cursor0`, `lxqt-menu-data`, `openbox`, `qt6-svg-plugins` (see the
  `lxqt` stage comment); the default panel drops the `volume` plugin
  (`/etc/xdg/lxqt/panel.conf`; no sound device, so it showed a red X). Check a
  new desktop with `tests/screenshot.sh`.
- **Ubuntu's `gnome` is GNOME Flashback**, not GNOME Shell: Shell 50 is Wayland-only and
  needs logind (tried with a mock logind + PipeWire + `--devkit`: it only
  half-started). No `gnome-session` either (needs systemd), so `vnc-session`
  starts `metacity`, `gnome-flashback` and `gnome-panel` itself and the session
  lasts as long as the panel; a menu entry (`vnc-logout.desktop`) stands in
  for Log Out. The panel layout is forced to `gnome-flashback` (Ubuntu's
  default wants an indicator applet that isn't installed). gnome-flashback's
  `screensaver` component is off (it locked after 5 idle minutes; no password).
- **Debian** (`debian/`): only Debian's default desktop, GNOME, as stage
  `gnome`. Instances have their own names, homes and ports (see the instance
  entry below). Debian's `gnome` is real
  **GNOME Shell** (GNOME 48 still has an X11 session). `gnome-session` without
  systemd falls back to starting the session itself, but aborts without a
  *system* bus, so `vnc-session` starts a stand-in `dbus-daemon` as the user
  (`/usr/local/share/vnc-system-bus.conf`, no services: logind/polkit/UPower
  warnings in the log are expected) at `$XDG_RUNTIME_DIR/system_bus_socket`,
  and runs `gnome-session --disable-acceleration-check` (the check rejects
  llvmpipe; Shell runs fine on it). No lock possible: without GDM, Shell creates
  no screen shield (`org.gnome.ScreenSaver.Lock` and Super+L find nothing);
  lock/idle settings are off too. `always-show-log-out` makes Power Off →
  Log Out… appear for the single user; it ends the session, so the container stops.
  Dash favourites forced to Chrome, Files, Terminal (Debian's list is mostly
  uninstalled apps). No `claude-desktop` (decided). Debian's gdk-pixbuf has no
  glycin, so the `NET_RAW`/`bwrap` gotcha doesn't break GTK there. Debian's
  `ping` ships without file caps (it relies on `ping_group_range`, "0 0" in the
  container), so `base` does `setcap cap_net_raw=ep /usr/bin/ping` like Ubuntu's.
- **`claude-desktop`** (the Claude desktop app) is in Ubuntu's `gnome` stage only, on
  purpose: it is still in beta, so don't add it to the other desktop stages. It
  comes from Anthropic's apt repository: the Containerfile downloads the signing
  key (`https://downloads.claude.ai/keys/claude-code.asc`) and writes
  `claude-desktop.list` to the paths the package's own postinst uses, then
  `apt-get install` (with recommends, unlike the desktop package lists;
  `gnome-keyring` is named explicitly because the app needs it). Not the
  .deb-download pattern used for Chrome: the only known .deb URL is versioned.
  It stores secrets in
  the default keyring (gnome-keyring, D-Bus activated). A new home has none, and
  gnome-keyring's "choose a password" dialog left the app hanging, so `gnome`'s
  `vnc-session` writes a passwordless plain-text keyring
  (`~/.local/share/keyrings/Default_keyring.keyring` + `default`) when the home
  has no `default`: it unlocks without a prompt. `gnome-keyring-daemon --unlock`
  with an empty password does *not* create a keyring. Secrets are unencrypted
  on purpose (no user password). To test, start the app with the session's
  `DBUS_SESSION_BUS_ADDRESS` (from `/proc/$(pgrep -x gnome-panel)/environ`):
  a plain `podman exec` has no session bus.
- **`kde`** is Plasma's X11 session (`plasma-session-x11`, `kwin-x11`; works
  without systemd). Screen locking is off by kiosk restriction
  (`/etc/xdg/kdeglobals`, `kscreenlockerrc`): the user has no password, so a
  locked screen can't be unlocked. A plasmashell update script
  (`vnc-desktop-launchers.js`) sets the pinned launchers once per home, as
  the built-in defaults include Discover, which isn't installed.
- **`mate`**: panel layout forced to MATE's `default` (Ubuntu's `familiar`
  wants applets that aren't installed: "Error" boxes, empty top panel);
  `scrot` for screenshots, as `mate-screenshot` only saves through a dialog.
- **`cinnamon`** uses the `cinnamon2d` (software rendering) session.
  `cinnamon-screensaver` is removed from the session's components and its
  D-Bus activation file deleted: gsettings alone (lock off, lockdown) don't
  stop an explicit lock request, and the user has no password to unlock with.
  **Any new desktop stage: check that the screen can't lock.**
- **Chrome** runs via the `/usr/local/bin/google-chrome-stable` wrapper
  (`--no-sandbox` etc.); `~/.config/chrome-flags.conf` does nothing on Ubuntu.
- **Ports bind all interfaces** on purpose (trusted LAN). Accepted.
- `PODMAN_USERNS=keep-id`; container user `ed` is UID 1001 by default, same as on the host.
- `label=disable` (not `:z`) on mounts.
- **Nested podman** (every stage): `/etc/subuid`/`subgid` are `ed:1:1000` +
  `ed:1002:64534` (subgid also `ed:0:1`, below), because the outer rootless container only has UIDs 0–65535;
  `containers.conf.d/nested.conf` disables cgroups and uses file events (no
  systemd), and sets `utsns = "host"` (outer seccomp blocks `sethostname`).
  `newuidmap`/`newgidmap` use file caps, not setuid (setuid-root gets EPERM
  on `uid_map`). Those subids and caps are only build-time defaults:
  `nested-subids` rewrites the subids from `/proc/self/{uid,gid}_map` extents
  and re-applies the caps at every boot, so a desktop nested in an instance
  (`ccNu_Md`) works too. `/etc/subgid` also gets `ed:0:1` (the
  instance's root group), so root in a nested build can write the shared apt
  cache's `partial/` (`_apt:root`, 700); podman sorts it to nested gid 1, which
  shifted nested gids by one, so older nested storage needs one
  `podman system reset` (`start.sh` warns; marker `~/.local/share/containers/.subgid-root-mapped`).
  `d_run` passes `/dev/fuse`,  `/dev/net/tun` and `unmask=/proc/*` (needed for nested `proc` mounts).
  An instance created before `d_run` added `unmask=/proc/*` needs recreating with `d_run`.
  Nested storage is in the instance's `~/.local/share/containers`, owned by mapped
  sub-IDs (delete it with `podman unshare rm -rf`, also from the host); ports a nested
  container publishes are reachable only inside the instance, so connect from there
  (`d_vnc`). `d_run` omits `--hostname` when `$container` is set (it wouldn't work).
  Without a `.env`, a nested desktop gets a copy of this instance's VNC password file.
  No seccomp or further relaxation: ask before adding any.
- Instance N (1-49) → container `ccN` + first letter of `d_distro` (`cc1u`,
  `cc1d`), same hostname; home `${d_homes0[<distro>]}N`, default
  `$d_dir/<image name>N` (`u2604cc1`, `d13cc1`; an old `.env`'s `d_home0` is
  Ubuntu's). When `d_run` runs nested (`$container` set) it's
  `<this instance>_N<letter>` (e.g. `cc2u_1d`, then `cc2u_1d_1u`), home
  `~/Containers/<that name>`, with no `--hostname`; the parent's name comes
  from `$D_NAME`, which `d_run` sets (nested instances share the hostname),
  falling back to `$HOSTNAME`. Ports: Ubuntu 6900+N (VNC) / 6080+N (noVNC),
  Debian 6950+N / 6130+N, so both distros' instance N can run at once.
  `d_select N` keeps only N; `_d_names` works out name, home and ports from
  the current `d_distro` in every function that needs them (via
  `_d_need_instance`), so `d_select 1; d_distro=debian d_run` is `cc1d`.

## Conventions
- `env.rc`: build podman commands as bash arrays, `echo` then run; quote
  expansions; functions that need an instance call `_d_need_instance`.
- `start.sh` runs under `set -e`: make first-boot steps idempotent and
  non-failing on re-run.
- Update README when a change is user-visible.
- Commit only when asked, directly on `main` (no feature branches; the user
  usually tries a change on the host first, then says "commit this"). Never
  push. Desktop variants are stages in their distro's `Containerfile` (not branches).

## Testing a change from inside an instance
You are `ed` with **no root** here (`sudo` only runs `nested-subids`), and the
image has no apt lists. Everything below uses the nested podman.
- **Build**: `source ./env.rc; [d_distro=debian] d_target=<stage> d_build > LOG 2>&1` — takes
  minutes (use a long timeout, log to a file, check the exit status). Changing
  `start.sh` or anything in `base` rebuilds every later stage.
- **Run a throwaway instance**: `d_run_new` (picks a free number), then
  `[d_distro=debian] d_target=<stage> d_run`. It is `<this instance>_N<letter>`, e.g. `cc1u_1u`, with home
  `~/Containers/cc1u_1u`, which is directly readable here: copy files in and
  out with plain `cp` (e.g. `cp -r tests ~/Containers/cc1u_1u/`), no `podman cp`
  needed. No `.env` is needed: it gets a copy of this instance's VNC password.
- **Look at it**: `podman exec cc1u_1u /home/ed/tests/screenshot.sh /home/ed/s.png`,
  then Read `~/Containers/cc1u_1u/s.png`. Give a desktop 15-40 s to come up first.
  Start GUI apps with `podman exec -d cc1u_1u <app>` (DISPLAY is already set).
- **Root for experiments**: `podman exec -u root cc1u_1u sh -c 'apt-get update &&
  apt-get install -y …'` (try packages there before editing the Containerfile;
  `xdotool` is handy for keys/clicks). To query apt without an instance:
  `podman run --rm --user root u2604cc:chrome sh -c 'apt-get update -qq; apt-cache policy PKG'`.
- **Checks worth repeating** for any stage: `tests/tests.sh` inside it (4 ok);
  `podman inspect` and process environments contain no `VNC_PASSWORD`;
  `sudo -n true` is refused; noVNC answers on `http://127.0.0.1:<6080+N, Debian 6130+N>/vnc.html`
  and `[::1]`; ending the session stops the container (`podman ps -a` shows
  Exited, log says "vncserver exited") and `podman start` brings it back.
- **Clean up** what you started: `podman rm -f -t 2 cc1u_1u` then
  `podman unshare rm -rf ~/Containers/cc1u_1u` (plain `rm` fails on sub-ID-owned
  files). `podman rm` sometimes prints an `openByHandleAt` error about exec
  sessions; run it again and check `podman ps -a`.
- **Not testable here**: the real host (NFS apt cache, host paths, other UIDs).
  Say so instead of guessing; the user tests on the host.

## Adding a desktop stage (checklist)
1. `<distro>/Containerfile`: `FROM chrome AS <name>`, `USER root`, one sorted apt `RUN`
   with the standard tail, a `RUN` writing `/usr/local/bin/vnc-session`, then
   `USER ${USERID}`; add the stage to the list in the header comment.
2. Find out what works before writing it: is there an X11 session at all
   (GNOME Shell: no), does its session manager need systemd/logind (start
   the parts by hand if so, as in `gnome`)? Try it in a throwaway instance.
3. Look at a screenshot of a **fresh home**. Ubuntu's default panel layouts
   often reference applets that `--no-install-recommends` leaves out (empty
   panel, "Error" boxes, blank icons): fix with a gsettings override in
   `/usr/share/glib-2.0/schemas/99_vnc-desktop.gschema.override` +
   `glib-compile-schemas --strict`, as in `gnome`/`mate`/`cinnamon`.
4. **Screen lock must be impossible** (no password to unlock): test an explicit
   lock request and the keyboard shortcut, not just the settings.
5. Log out from the desktop must end the session (so the container stops), or
   provide a replacement and document it.
6. A screenshot tool that can save to a file without a dialog (`scrot` if
   the desktop's own can't), and a branch for it in `tests/screenshot.sh`.
7. `env.rc`: add to `d_targets_<distro>` and the `d_target` comment.
8. Docs: README (intro sentence, file table, Stages text and table, Screenshots
   item, `d_all` list), this file (intro, Files, design decisions), and
   `docs/<distro>/` (`d_distro=<distro> d_screenshots N <name>`, plus a section in `docs/README.md`).

## Gotchas met so far
- `[ -s FILE ]` is always false for `/proc` files (size 0): test the content.
- `localhost` may resolve to `::1` first; a published port whose service only
  listens on IPv4 then accepts and resets. Use `127.0.0.1` in checks.
- `pgrep NAME` matches only the first 15 characters of a process name; use
  `pgrep -f` for longer ones.
- `sed` succeeds when nothing matched: in the Containerfile, pair an edit of a
  packaged file with a `grep -q` so an upstream change fails the build.
- A gsettings override only changes defaults: a home that already set the key
  keeps its value, so test on a fresh home.
- Thread/process spawn failing with EAGAIN ("Resource temporarily unavailable",
  e.g. claude-desktop's tokio panic) is the instance's cgroup pids limit: nested
  containers have no cgroup of their own (`cgroups = "disabled"`), so all of them
  count against the outer instance's `pids.max`. Check `/sys/fs/cgroup/pids.max`,
  `pids.current`, `pids.peak` and `pids.events` (count of refused spawns). KDE alone
  is ~550 threads. `d_run` sets `--pids-limit $d_pids_limit` (16384; podman's default
  is 2048); it can't be raised from inside, only by recreating the instance on the
  host. Nested, the flag is accepted but has no effect.
- `$VNC_PASSWORD` may still be in this instance's environment (instances
  created before the `passwd.init` change); never print it.
- `--cap-add` (e.g. `NET_RAW` in `d_run_opts`, for ping) makes the cap *ambient*
  for the non-root user, so every process holds it, and `bwrap` then refuses to run
  ("Unexpected capabilities but not setuid"). Desktops load icons via gdk-pixbuf →
  glycin → `bwrap`, so the session aborted (signal 6, "Could not load a pixbuf").
  `start.sh` therefore re-execs itself under `setpriv --inh-caps=-all
  --ambient-caps=-all`: the cap stays in the bounding set, so file-cap binaries
  (`ping`: `cap_net_raw=ep`) still get it. `podman exec` processes still have the
  ambient cap: prefix GUI apps (and `tests/screenshot.sh`) with that `setpriv`.
  Check with `grep Cap /proc/<pid>/status`.
