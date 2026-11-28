# AGENTS.md — vnc-desktop-podman

Rootless-podman images over TigerVNC/noVNC, with Google Chrome (Chromium on Arch),
coding-agent CLI installers, `vnc-pkg`, and nested rootless podman, in three layers:
- **distros** `ubuntu` (26.04), `debian` (13 trixie), `fedora` (45), `archlinux` (rolling):
  `container/deb/Containerfile` (shared by Ubuntu and Debian via `DISTRO`/`USER_FILES_GLOB`),
  `container/fedora/Containerfile`, `container/archlinux/Containerfile`, stages `base` → `vnc` → `browser`;
- **desktops** on a distro's `browser`: `container/<desktop>/Containerfile`, one stage per
  distro that has it: Ubuntu `xfce`, `lxqt`, `gnome` (Flashback), `kde`, `mate`, `cinnamon`;
  Debian `gnome` (Shell); Fedora `xfce`, `lxqt`; Arch `openbox`;
- **agent desktops** `<desktop>-<agent>` on a desktop: `container/<agent>/Containerfile`:
  `lxqt-opencode`, `lxqt-antigravity` (Ubuntu, Fedora), `gnome-opencode`,
  `gnome-antigravity`, `gnome-claude` (Ubuntu); an agent's `ubuntu` stage works on any
  Ubuntu desktop (`BASE` is the desktop image);
plus `devtools` (`container/chrome/`, Chrome automation on Ubuntu's `browser`).

Images are tagged `vnc-desktop-<distro>:<target>[-<version>]` (Ubuntu `2604`, Debian `13`,
Fedora `45`, Arch rolling/none). Everything images build from lives under `container/`;
the top level has user-facing files (`env.rc`, `.env`, `README.md`, `docs/`, `tests/`,
`user_files/`, `chrome/`). See `README.md` for user setup.

## On-demand skills (`.agents/skills/`)
Detailed procedural runbooks live in `.agents/skills/` (discovered automatically by
Antigravity and OpenCode, and by Claude Code through the `.claude/skills` symlink; read
directly if using an agent that doesn't auto-load them):
- `.agents/skills/nested-testing/SKILL.md` — building, running, screenshotting, and testing
  changes inside a nested podman instance.
- `.agents/skills/add-desktop/SKILL.md` — checklist for adding a distro desktop or a new
  distro stage to an existing desktop.
- `.agents/skills/add-agent-desktop/SKILL.md` — checklist for adding an agent desktop
  (`<desktop>-<agent>`).

## Repository layout

Under `container/` (build context is always the repo root):
- `deb/Containerfile` — shared by Ubuntu 26.04 and Debian 13 trixie (`ARG DISTRO`,
  `ARG USER_FILES_GLOB`), stages `base` → `vnc` → `browser`. Package lists are **sorted**.
- `fedora/Containerfile` — Fedora 45 (`registry.fedoraproject.org/fedora:45`), dnf5.
- `archlinux/Containerfile` — Arch Linux (rolling, amd64 only), pacman, Chromium in `browser`.
- `xfce/`, `lxqt/`, `gnome/`, `kde/`, `mate/`, `cinnamon/`, `openbox/` — desktop
  `Containerfile`s (`ARG BASE`, one stage per supported distro named `<distro>`).
- `opencode/`, `antigravity/`, `claude/` — agent desktop `Containerfile`s + `README.md`
  (keep main `README.md`'s Agent desktops table in sync).
  - `opencode`: Electron `.deb`/`.rpm` from opencode.ai's "latest" URL (not GitHub);
    shared `setup-opencode.sh` installs `/usr/local/bin/ai.opencode` (`--no-sandbox
    --password-store=basic`), patches `.desktop` files, symlinks `opencode` to
    `/opt/OpenCode/resources/opencode-cli`. App copies CLI (~240 MB) to
    `~/.config/ai.opencode.desktop/cli/<ver>/` on start; updater can't run without root.
  - `antigravity`: shared `app` stage (tarball from hub updater `/releases` JSON,
    `ANTIGRAVITY_VERSION`/`ANTIGRAVITY_TGZ` override, `linux-x64`/`linux-arm`, `ldd` check,
    wrapper + `antigravity.desktop`, Python SDK `google-antigravity` in user-owned
    `/opt/venv` with `uv` in `/opt/uv`); `ubuntu` and `fedora` are `FROM app`.
  - `claude`: `ubuntu` on `gnome` only (beta); Anthropic apt repo + `gnome-keyring` +
    wrapper seeding a passwordless plaintext keyring when `~/.local/share/keyrings/default`
    is absent.
- `chrome/Containerfile` — `d_target=devtools` (`ubuntu` on `browser`): Chrome Canary
  wrapper, Openbox + xterm, `scrot`, `socat`, `ffmpeg`, `x11-utils`, global npm tools
  (`chrome-devtools-mcp`, `@playwright/mcp`, `puppeteer-core`, `playwright-core`,
  `lighthouse`, `NODE_PATH`), user-owned `/opt/uv` + `/opt/venv` (`playwright`), and
  `install_chrome_devtools`.
- `cli-installers/` — `install_claude`, `install_agy`, `install_opencode`, `install_grok`,
  `install_t3code`: copied to `/usr/local/bin` in every `browser` stage; run by user into
  home volume, self-updating.
- `vncserver-wrapper` — `/usr/local/bin/vncserver` in every `vnc` stage; foreground
  `Xtigervnc`/`Xvnc` + `xstartup`, sets `XDG_SESSION_TYPE=x11` etc., exits when either ends.
- `start.sh` — entrypoint (under `--init`, `set -e`): strips ambient caps (`setpriv`),
  exports `$SHELL` from passwd, first-boot home seeding (`/etc/skel`, guarded `~/.local/bin`
  PATH, `user_files.tar`, `D_NAME` prompt), runs `sudo /usr/local/sbin/nested-subids`,
  converts/deletes `passwd.init`, starts `vncserver -fg` + `websockify` (or `sleep infinity`
  for `base`).
- `nested-subids` — `/usr/local/sbin/nested-subids`, run via `sudo` at boot to fit
  `/etc/subuid`/`/etc/subgid` and `newuidmap`/`newgidmap` file caps to the container.
- `vnc-pkg` — `/usr/local/sbin/vnc-pkg` (sudo-allowed) + `/usr/local/bin/vnc-pkg` wrapper:
  `vnc-pkg {upgrade|install PKG...|remove PKG...}` for repo packages across apt/dnf/pacman;
  strict package-name validation, cleans cache/lists, drops root via `setpriv` to write
  `~/.config/vnc-desktop/{pkg.log,commit-requested}` for `d_commit` / `d_commit_watch`.
  `d_commit` writes the instance's own tag `<image>:<tag>-<VNC port>` (`$d_commit_image`),
  never the built `<image>:<tag>`: `d_run`/`d_run_cmd` start it when it exists (warning
  when the built image is newer), `d_uncommit` and `d_rm` remove it, `d_test` and
  `d_screenshots` ignore it (`d_use_commit=0`). Desktops and agents build on the built
  images only. Open issues: `TODO.md`.

Top-level files:
- `env.rc` — host/nested bash helpers (`d_0`, `d_pull`, `d_build`, `d_build_fresh`, `d_select`,
  `d_run_new`, `d_run`, `d_run_cmd`, `d_vnc`, `d_novnc`, `d_logs`, `d_commit`,
  `d_commit_watch`, `d_uncommit`, `d_exec`, `d_all`, `d_screenshots`, `d_test`, `d_rm`). Maps
  `ubuntu`/`debian` → `deb/` and `devtools` → `chrome/` via `d_dirs`. Labels every built
  image with `org.opencontainers.image.description` from `d_desc_distros`/`d_descs` (**add
  new distros/targets there**).
- `.containerignore` — allow-list for repo-root build context (`LICENSE`,
  `container/{start.sh,nested-subids,vnc-pkg,vncserver-wrapper,cli-installers,opencode/setup-opencode.sh}`,
  `user_files`). **Any new `COPY` source needs a `!` line here.**
- `chrome/env.rc` — sourced by `env.rc`: `d_chrome`, `d_chrome_mcp`, `d_devtools`.
- `tests/` — `tests.sh` (nested podman), `test_env.sh` (stubbed-`podman` unit tests, run in
  `.github/workflows/ci.yml` with `shellcheck`), `screenshot.sh`, `lock.sh`.
- `docs/` — `README.md` screenshot gallery (`docs/<distro>/<target>.png`) and
  `Advantages-article.md`.
- `.env` — local `VNC_PASSWORD` and overrides (gitignored; **never commit or print**).

## Where you are probably running
Coding agents usually run *inside* an instance with this repo on the home volume. When
`$container` is set, `env.rc` switches to nested paths (`d_dir=/home/$d_user/Containers`,
instance `<parent>_<image>-<tag>-<port>`, `/var/cache/apt-<distro>` cache mounts, no
`--hostname`), so `d_build`/`d_run` operate on the nested podman, never the host's. Host
NFS paths and other UIDs are not testable inside an instance — say so instead of guessing.
See `.agents/skills/nested-testing/SKILL.md` for full testing commands.

## Design decisions (don't undo without asking)
- **Home is a volume** (`$d_home` → `/home/$d_user`). Build-time files in `/home/$d_user`
  are hidden; per-user setup belongs in `start.sh` (idempotent first-boot guards) or
  runtime. Optional `user_files/<distro>/` (gitignored, user's private files — don't edit
  or print) is packed into `/usr/local/share/user_files.tar` via bracket-glob `COPY` with
  `LICENSE` sentinel and unpacked on first boot over `/etc/skel`.
- **Agent CLIs** (`install_claude`, `install_agy`, `install_opencode`, `install_grok`,
  `install_t3code`) install at runtime into the home volume, not baked into images. Shared
  CLI tools (`fd`/`fd-find`, `fzf`, `zstd`) live in `base`; `featherpad` in `lxqt`. Grok
  and T3 Code are CLI installers only (no agent desktops).
- **Shared per-distro package caches** (NFS-shareable, not buildah cache mounts): host
  `$d_dir/apt-cache-<distro>/archives` (or `d_aptcaches[<distro>]`) mounted at
  `/var/cache/apt-<distro>` (apt `.deb`s, dnf rpms+metadata, pacman packages). `d_run`
  mounts every cache that exists for nested builds. Every package `RUN` keeps its distro's
  cleanup tail (`mountpoint -q /var/cache/apt-<distro> || <clean>` + remove lists/sync DBs).
- **VNC password** never goes in the container env: `d_run` writes mode-600 `passwd.init`
  (or nested copies parent's `passwd`); `start.sh` runs `vncpasswd -f`, deletes
  `passwd.init`, and unsets `VNC_PASSWORD`.
- **No general root for the user**: no `sudo` group or blanket rule; sudoers allows only
  `/usr/local/sbin/nested-subids ""` (no args) and `/usr/local/sbin/vnc-pkg` (strictly
  validated repo package upgrade/install/remove). `sudo -n true` stays refused.
- **User, UID, and GID** are build args (`USERID`, `USER_UID`, `USER_GID` from `$d_user`,
  `id -u`, `id -g`) so `PODMAN_USERNS=keep-id` lines up for any host user. Scripts use
  `$USERID` / `$SUDO_USER`, not a literal `ed`. `d_user` defaults to `${USER:-ed}` and
  `d_dir` to `${XDG_DATA_HOME:-$HOME/.local/share}/vnc-desktop` (override in `.env`).
- **Session comes from the image** (`/usr/local/bin/vnc-session`); `~/.config/tigervnc/xstartup`
  only runs it under `dbus-launch`, so homes work across images. Shared `vncserver-wrapper`
  is used everywhere; `_d_session_sh` finds the session as its non-X-server child.
- **No screen locking on any desktop**: the container user has no password to unlock with.
  Always verify with `tests/lock.sh`.
- **Desktop specifics**:
  - Ubuntu `lxqt`: needs `breeze-icon-theme`, `libxcb-cursor0`, `lxqt-menu-data`, `openbox`,
    `qt6-svg-plugins` without recommends; drops panel `volume` plugin (red X, no audio).
  - Ubuntu `gnome`: GNOME Flashback (Shell 50 is Wayland-only/needs logind); `vnc-session`
    starts `metacity`, `gnome-flashback`, `gnome-panel` directly; `vnc-logout.desktop`
    stands in for Log Out; `default-layout='gnome-flashback'`, `screensaver=false`.
    `seahorse` is included for keyring inspection.
  - Debian `gnome`: GNOME 48 X11 Shell with stand-in per-user system `dbus-daemon`
    (`/usr/local/share/vnc-system-bus.conf`), `--disable-acceleration-check`,
    `always-show-log-out=true`, trimmed dash favourites. No `claude-desktop`.
  - Ubuntu `kde`: Plasma X11 (`plasma-session-x11`, `kwin-x11`), kiosk lock restriction
    (`kdeglobals`, `kscreenlockerrc`), `vnc-desktop-launchers.js` drops Discover.
  - Ubuntu `mate`: `default-layout='default'` (Ubuntu's `familiar` has missing applets),
    `scrot` for screenshots, build asserts `! command -v mate-screensaver`.
  - Ubuntu `cinnamon`: `cinnamon2d` software session; `cinnamon-screensaver` removed from
    session components and D-Bus activation deleted.
  - Fedora: named packages (not `@*-desktop` groups), `install_weak_deps=False`,
    `startlxqt` in `lxqt-x11-session`, `xfce-polkit.desktop` removed, `TMPDIR=/tmp` in
    `nested.conf`, `pasta` hard-linked if symlinked.
  - Arch Linux (amd64 only; unset on `aarch64` in `env.rc`): `pacman -Syu` only,
    `DownloadUser` commented out, `vnc-session` runs `eval "$(dbus-launch --sh-syntax)"`
    (Arch's `dbus-launch` lacks X11 support), noVNC tarball + websockify venv, `pasta`
    hard-linked (Ubuntu host AppArmor profile path matching), `TMPDIR=/tmp` in
    `nested.conf`, Chromium via `/etc/chromium-flags.conf`, custom Openbox `menu.xml`.
- **Architectures**: Ubuntu, Debian, Fedora, Chrome, OpenCode, Antigravity, and Claude
  Desktop build on amd64 and arm64 (`dpkg --print-architecture` / `uname -m`). Keep changes
  architecture-neutral; Arch is amd64-only.
- **Networking & ports**: Published on all interfaces by default (trusted LAN);
  `d_bind=127.0.0.1` in `.env` restricts `d_run` to localhost. Default `d_run_opts` is
  `("-d" "--cap-add=NET_RAW")`; debug `pasta` host-gateway flags are opt-in in `.env`.
  `label=disable` (not `:z`) on mounts.
- **Port & instance scheme** (N = 1..49): `<image>-<tag>-<VNC port>` (nested:
  `<parent>_<name>`). VNC / noVNC bases: ubuntu 6900/6080, debian 6950/6130, devtools
  7000/6180, archlinux 7050/6230, opencode 7150/6330, antigravity 7200/6380, fedora
  7350/6530, claude 7400/6580 (7100/6280 reserved for omarchy). Same distro/layer shares
  ports across targets; `d_run_new`, `d_screenshots`, and `d_test` check `_d_port_used`.
- **Nested podman**: `/etc/subuid`/`/etc/subgid` fit inside 0..65535 (`subgid` adds
  `<user>:0:1` so nested root can write shared apt cache `partial/`); `newuidmap`/`newgidmap`
  use file caps (not setuid); `nested.conf` sets `cgroups = "disabled"`, `utsns = "host"`,
  `events_logger = "file"`; `d_run` passes `/dev/fuse`, `/dev/net/tun`, `unmask=/proc/*`,
  `--pids-limit $d_pids_limit` (16384). No seccomp relaxation without asking.
- **Chrome automation**: DevTools port (`127.0.0.1:9222`) stays inside the instance (never
  published); requires non-default `--user-data-dir` (Chrome 136+).
- **No legacy compatibility needed**: prefer the clean scheme.

## Conventions
- `env.rc`: build podman commands as bash arrays, `echo` then run; quote expansions;
  functions needing an instance call `_d_need_instance`; keep `shellcheck` clean (0 warnings)
  and `tests/test_env.sh` passing.
- `start.sh` runs under `set -e`: keep first-boot blocks idempotent.
- Update `README.md` (and `AGENTS.md` / skills) for user-visible or structural changes.
- Commit only when asked, directly on `main` (no feature branches). **Never push.**

## Gotchas
- **Open (pasta debug)**: with optional `d_run_opts` `--network=pasta:-T,5201,--map-gw`
  (put `-T` before `--map-gw` on podman 4.9), `iperf3` to parent 5201 wasn't working when
  tested (`-T 5201` maps container `127.0.0.1:5201` → host `127.0.0.1:5201`; `--map-gw`
  routes to the host's non-loopback gateway IP).  See `TODO.md`.
- `[ -s FILE ]` is always false on `/proc` files (size 0): read content instead.
- `localhost` may resolve to `::1` first; use `127.0.0.1` for IPv4 checks/connections.
- `pgrep NAME` matches only the first 15 chars; use `pgrep -f` for longer names.
- `sed` succeeds on zero matches: pair Containerfile `sed` edits with `grep -q` assertions.
- GSettings overrides only affect defaults; test on a fresh home.
- EAGAIN thread/process spawn errors (`tokio` panics, etc.) hit the outer cgroup
  `pids.max` (`d_pids_limit=16384`); nested containers share the parent's cgroup.
- `SHELL` isn't set by podman: `start.sh` exports it from passwd; `podman exec` lacks it.
- `--cap-add=NET_RAW` creates ambient caps for non-root, breaking `bwrap`/glycin/GTK icon
  loading: `start.sh` and `d_exec` strip ambient/inheritable caps with
  `setpriv --inh-caps=-all --ambient-caps=-all` (bounding set still allows `ping` file caps).
- `podman exec` puts `/usr/local/sbin` before `/usr/local/bin` on `PATH` (handled in
  `vnc-pkg` via self-elevation).
- `podman commit` defaults to OCI format (rejects `-m`; use `--pause=false` for cgroup-less
  nested podman).
- Never print `$VNC_PASSWORD` or `.env`.
