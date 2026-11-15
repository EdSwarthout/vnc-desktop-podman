# CLAUDE.md — vnc-desktop-podman

Rootless-podman image: Ubuntu 26.04 + XFCE or LXQt over TigerVNC/noVNC, with
Chrome, Claude Code and nested podman (plus smaller headless/xterm stages).
See `README.md` for user-facing setup; `REVIEW.md` tracks review items and their status.

## Files
- `Containerfile` — stages `base` (headless + nested rootless podman) →
  `vnc` (TigerVNC/noVNC, xterm session) → `chrome` → `xfce` / `lxqt`.
  `d_target` in `env.rc` picks one (default `xfce`); images are tagged
  `u2604cc:<stage>`. Package lists are kept **sorted**.
- `start.sh` — entrypoint (PID 1's child under `--init`), shared by all stages:
  first-boot seeding of the home volume and `nested-subids`; then, if the
  stage has `vncserver`, runs `vncserver -fg` and `websockify` and exits when
  either does, so the container stops; otherwise (`base`) `exec sleep infinity`.
- `nested-subids` — `/usr/local/sbin`; `start.sh` runs it via `sudo` at every
  boot to fit subids and `newuidmap` caps to the container.
- `env.rc` — host-side bash helpers, `source`d from any cwd: `d_0`, `d_build`,
  `d_build_fresh`, `d_select N`, `d_run_new`, `d_run`, `d_vnc`, `d_logs`,
  `d_all N [STAGE...]` (build + run every stage on instances N, N+1, …, with
  `d_vnc` in the background).
- `tests/tests.sh` — nested-podman checks, run inside an instance.
   `tests/screenshot.sh` — full-screen PNG of `:1` via `xfce4-screenshooter` / `screengrab` (xfce, lxqt); copy it out
  with `podman cp` and look at it to check a desktop by script.
- `.env` — `export VNC_PASSWORD=…` (gitignored, never commit or print it).

## Where you're probably running
Claude Code usually runs *inside* an instance (e.g. `cc1`) with this repo on
the home volume. Every stage has a nested rootless podman
for scratch containers, but it is *not* the host's podman, and the host paths
(`$d_dir`, the NFS apt cache) are not visible. When `$container` is set, `env.rc`
switches to nested paths (`d_dir=~/Containers`, instance N named `<this instance>_N` with home `~/Containers/<this instance>_N`,
the instance's own apt cache mount, no `--hostname`), so `d_build`/`d_run` here
build and run a nested instance in the nested podman, not a host one. Check things in the container directly (`/proc/1/environ`,
`mountpoint /var/cache/apt/archives`, `~/.config/tigervnc`) and test `env.rc`
changes with a stubbed `podman`, both ways (`container=` for host behaviour):
```bash
bash -c 'podman(){ echo "[podman $*]"; }; mkdir(){ :; }; source ./env.rc; d_select 1; d_run'
container= bash -c 'podman(){ echo "[podman $*]"; }; mkdir(){ :; }; source ./env.rc; d_select 1; d_run'
```
The user builds, runs and pushes from the host. There is no git remote here.

## Design decisions (don't undo without asking)
- **Home is a volume** (`$d_dir/u2604ccN` → `/home/ed`). Anything put in
  `/home/ed` at build time is hidden; per-user setup belongs in `start.sh`'s
  first-boot blocks (guarded by "file doesn't exist yet") or runs at runtime.
- **Claude Code** is installed by the user at runtime via `install_claude`
  (native installer → `~/.local/bin`, self-updating). Not baked into the image.
- **Shared apt cache**: `$d_aptcache` (`$d_dir/apt-cache/archives`, NFS-shared
  between machines) is mounted on `/var/cache/apt/archives` in both build and
  run. `docker-clean` is replaced by `docker-no-pkgcache`; every apt `RUN` ends
  with `{ mountpoint -q /var/cache/apt/archives || apt-get clean; }` and
  `rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin`. Keep that tail on new
  apt `RUN`s. Not a buildah cache mount, because it must be shareable over NFS.
- **VNC password** is passed (`-e VNC_PASSWORD`) only while
  `~/.config/tigervnc/passwd` doesn't exist, so it doesn't stay in the
  container env / `podman inspect`.
- **Session comes from the image**: each stage with a display installs
  `/usr/local/bin/vnc-session` (xterm / `startxfce4` / `startlxqt`); the home's
  `xstartup` only runs it under `dbus-launch`, so a home works with any stage.
- **LXQt without recommends** needs explicit `breeze-icon-theme`,
  `libxcb-cursor0`, `lxqt-menu-data`, `openbox`, `qt6-svg-plugins` (see the
  `lxqt` stage comment); the default panel drops the `volume` plugin
  (`/etc/xdg/lxqt/panel.conf`; no sound device, so it showed a red X). Check a
  new desktop with `tests/screenshot.sh`.
- **Chrome** runs via the `/usr/local/bin/google-chrome-stable` wrapper
  (`--no-sandbox` etc.); `~/.config/chrome-flags.conf` does nothing on Ubuntu.
- **Ports bind all interfaces** on purpose (trusted LAN). Accepted.
- `PODMAN_USERNS=keep-id`; container user `ed` is UID 1001, same as on the host.
- `label=disable` (not `:z`) on mounts.
- **Nested podman** (every stage): `/etc/subuid`/`subgid` are `ed:1:1000` +
  `ed:1002:64534` (subgid also `ed:0:1`, below), because the outer rootless container only has UIDs 0–65535;
  `containers.conf.d/nested.conf` disables cgroups and uses file events (no
  systemd), and sets `utsns = "host"` (outer seccomp blocks `sethostname`).
  `newuidmap`/`newgidmap` use file caps, not setuid (setuid-root gets EPERM
  on `uid_map`). Those subids and caps are only build-time defaults:
  `nested-subids` rewrites the subids from `/proc/self/{uid,gid}_map` extents
  and re-applies the caps at every boot, so a desktop nested in an instance
  (`ccN_M`) works too. `/etc/subgid` also gets `ed:0:1` (the
  instance's root group), so root in a nested build can write the shared apt
  cache's `partial/` (`_apt:root`, 700); podman sorts it to nested gid 1, which
  shifted nested gids by one, so older nested storage needs one
  `podman system reset` (`start.sh` warns; marker `~/.local/share/containers/.subgid-root-mapped`).
  `d_run` passes `/dev/fuse`,  `/dev/net/tun` and `unmask=/proc/*` (needed for nested `proc` mounts).
  No seccomp or further relaxation: ask before adding any.
- Instance N → container `ccN`, hostname `ccN`; when `d_run` runs nested
  (`$container` set) it's `<this instance>_N` (e.g. `cc2_1`, then `cc2_1_1`)
  with no `--hostname`; the parent's name comes from `$D_NAME`, which `d_run`
  sets (nested instances share the hostname), falling back to `$HOSTNAME`. Ports 6900+N (VNC) and
  6080+N (noVNC).

## Conventions
- `env.rc`: build podman commands as bash arrays, `echo` then run; quote
  expansions; functions that need an instance call `_d_need_instance`.
- `start.sh` runs under `set -e`: make first-boot steps idempotent and
  non-failing on re-run.
- When fixing a REVIEW.md item: flip its status (✅ done · ➖ accepted · ⬜ open),
  add a `*Done (\`<commit>\`):*` note saying what changed and how it was
  checked, and update README if user-visible.
- Commit only when asked. Desktop variants are stages in the one
  `Containerfile` (not branches).
