# CLAUDE.md — vnc-desktop-podman

Rootless-podman image: Ubuntu 26.04 + XFCE, LXQt, GNOME Flashback, KDE Plasma, MATE or Cinnamon,
or Debian 13 (trixie) + GNOME Shell, or Arch Linux + Openbox, over TigerVNC/noVNC, with
Chrome (Chromium on Arch), Claude Code and nested podman (plus smaller headless/xterm stages),
and an OpenCode image on Ubuntu's LXQt (`opencode/`).
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
- `archlinux/Containerfile` — Arch Linux (rolling): `base` → `vnc` → `chromium` → `openbox`,
  tagged `archcc:<stage>`, `d_distro=archlinux`, instances `ccNa`, ports
  7050+N / 6230+N. `base`/`vnc` follow Debian's; what differs is under
  "Arch Linux" in the design decisions. `chromium` stands where `chrome` does.
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
  `docs/<distro>/<stage>.png` on a throwaway instance N), `d_test N [STAGE...]`
  (build, run on a throwaway instance N, check, remove: see "Testing a change"),
  `d_exec [-s] [-d] CMD` (`podman exec` minus ambient caps; `-s`: with the
  session's D-Bus/XDG environment), `d_rm [-f] [N]` (container **and home**; asks
  unless `-f`). `d_build` ends with a summary (time; apt "downloaded/needed" per
  apt step that ran, `0 B/…` = all from the shared cache; for archlinux, pacman
  "downloaded/installed" per step). `_d_wait_ready` waits
  for password file + noVNC + a visible window; `_d_rm` is `d_rm` without asking.
- `chrome/Containerfile` — `d_distro=chrome`, one stage `canary`, tagged
  `u2604chrome:canary`: `FROM localhost/u2604cc:chrome` (so `d_build` builds Ubuntu's
  `chrome` stage first: `d_parents[chrome]="ubuntu chrome"`, which also makes it use
  Ubuntu's apt cache) + `google-chrome-canary` (wrapper like stable's), Openbox +
  xterm session, `scrot`, `socat`, `ffmpeg`, and global npm tools
  (`chrome-devtools-mcp`, `@playwright/mcp`, `puppeteer-core`, `playwright-core`,
  `lighthouse`; `NODE_PATH` set), and Python's `playwright` in a venv made with
  `uv`: `/opt/uv/bin/uv` and `/opt/venv`, both owned by the user and outside the
  home volume, venv first on `PATH` and `VIRTUAL_ENV` set, so the user can
  `uv pip install` without root. `chrome/search_screenshot.py` is a Python example
  (web search → PNG via the DevTools port). `install_chrome_devtools` (run by the
  user, like `install_claude`) copies `chrome-devtools-mcp`'s bundled skills to
  `~/.claude/skills`. Instances `ccNc`, ports 7000+N / 6180+N.
- `opencode/Containerfile` — `d_distro=opencode`, one stage `lxqt`, tagged
  `u2604opencode:lxqt`: `FROM localhost/u2604cc:lxqt` (`d_parents[opencode]="ubuntu lxqt"`,
  as for chrome) + OpenCode Desktop (Electron `.deb` from opencode.ai's "latest" URL,
  not GitHub's; `/usr/local/bin/ai.opencode` wrapper with `--no-sandbox
  --password-store=basic`, both `.desktop` files pointed at it), `opencode` = a symlink
  to the desktop's bundled CLI (`/opt/OpenCode/resources/opencode-cli`, one copy), and
  `install_opencode` (run by the user, like `install_claude`: opencode's own build in
  `~/.opencode/bin`, self-updating, first on PATH via `.bashrc`); plus `fd-find`, `fzf`,
  `featherpad`. The app's own updater can't install a `.deb` without root: rebuild. The
  app copies its CLI into the home (`~/.config/ai.opencode.desktop/cli/<ver>/`, ~240 MB)
  and runs `opencode-cli serve` from there; no switch found to stop that.
  Instances `ocNu` (`d_name0s`/`d_letters` in `env.rc`; nested `<this>_ocNu`), ports
  7150+N / 6330+N (7100/6280 are the `research` branch's omarchy). `opencode/README.md`.
- `.containerignore` — `d_build`'s context is the repo root; this allow-list sends only
  `LICENSE`, `start.sh`, `nested-subids` and `*/user_files`. **A new `COPY` source needs
  a `!` line here.**
- `chrome/env.rc` — sourced by `env.rc`: `d_chrome [URL...]` (Chrome on the
  instance's desktop with the DevTools port, 127.0.0.1:9222 inside the instance,
  profile `~/.config/chrome-automation`) and `d_chrome_mcp` (prints the `claude mcp
  add` line for `chrome-devtools-mcp` run in the instance via `podman exec -i`: the
  image's binary if there is one, else `npx`). `d_chrome_bin=google-chrome-canary`
  for Canary. `d_devtools CMD...` runs the `chrome-devtools` CLI (same tools as the
  MCP server; daemon in the instance, started on demand) in a `canary` instance.
  Both get `_d_devtools_opts`: `--browserUrl`, no usage statistics, no CrUX,
  `--workspace=/home/<user>` (+ `d_devtools_opts`).
  `chrome/README.md` — the automation options compared, and what has been tried.
- `tests/tests.sh` — nested-podman checks, run inside an instance.
   `tests/screenshot.sh` — full-screen PNG of `:1` via `xfce4-screenshooter` / `screengrab` / `gnome-screenshot` / `spectacle` / `scrot` (xfce, lxqt, gnome, kde, mate + cinnamon); copy it out
  with `podman cp` and look at it to check a desktop by script.
   `tests/lock.sh` — sends every lock request it knows (screensaver D-Bus names,
  desktops' lock commands, Super+L, Ctrl+Alt+L) and after each types into its own
  xterm with `xdotool` (XTEST, which a locker's grab would divert): FAIL if the
  text doesn't arrive. Needs the session bus (`d_exec -s`); throwaway instances only.
- `docs/` — `README.md` gallery with one screenshot per stage of the desktop
  on a fresh home (`ubuntu/<stage>.png`, `debian/<stage>.png`, `archlinux/<stage>.png`); retake a stage's picture when its initial
  look changes (`[d_distro=debian] d_screenshots N <stage>`).
- `.env` — `export VNC_PASSWORD=…` and local settings such as `d_dir=…`
  (gitignored, never commit or print it). Usually absent inside an instance.

## Where you're probably running
Claude Code usually runs *inside* an instance (e.g. `cc1u`) with this repo on
the home volume. Every stage has a nested rootless podman
for scratch containers, but it is *not* the host's podman, and the host paths
(`$d_dir`, the NFS apt cache) are not visible. When `$container` is set, `env.rc`
switches to nested paths (`d_dir=~/Containers`, instance N named `<this instance>_N<distro letter>` (e.g. `cc1u_1d`) with home `~/Containers/<that name>`,
the instance's `/var/cache/apt-<distro>` cache mounts, no `--hostname`), so `d_build`/`d_run` here
build and run a nested instance in the nested podman, not a host one. Check things in the container directly (`/proc/1/environ`,
`mountpoint /var/cache/apt-ubuntu /var/cache/apt-debian`, `~/.config/tigervnc`) and test `env.rc`
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
- **Shared apt caches**, one per distro (same file names, different
  contents), NFS-shared between machines: host `$d_dir/apt-cache-<distro>/archives`
  (`apt-cache-ubuntu`, `apt-cache-debian`), or
  `d_aptcaches[<distro>]` from `.env`. Each image's apt keeps `.deb`s in
  `/var/cache/apt-<distro>` (`Dir::Cache::archives`, apt.conf.d
  `vnc-desktop-archives`; apt creates the dir when nothing's mounted).
  `d_build` mounts the distro's cache there; `d_run` mounts every distro's
  that exists (`/var/cache/apt-ubuntu`, `/var/cache/apt-debian`), and nested,
  `env.rc` uses those mounts, so nested builds of either distro get their own
  cache. `docker-clean` is replaced by `docker-no-pkgcache`; every apt `RUN` ends
  with `{ mountpoint -q /var/cache/apt-<distro> || apt-get clean; }` and
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
- **Arch Linux** (`archlinux/`): stages `base`, `vnc`, `chromium`, `openbox`; the shared
  `start.sh` and `nested-subids` run unchanged, so the image adapts to them:
  - *Package cache*: same scheme and names as apt's (`apt-cache-archlinux`,
    `/var/cache/apt-archlinux`, `d_aptcaches[archlinux]`), holding pacman's
    packages: `pacman.conf` gets `CacheDir = /var/cache/apt-archlinux/` and loses
    `DownloadUser` (it chowns its download dir to `alpm`, which a shared cache
    can't do). Every pacman `RUN` is `pacman -Syu --noconfirm --needed …` (never
    `-Sy`: no partial upgrades) with the tail `{ mountpoint -q
    /var/cache/apt-archlinux || rm -rf /var/cache/apt-archlinux/*; } && rm -rf
    /var/lib/pacman/sync/*`. So an instance has no sync databases: as root,
    `pacman -Syu --needed PKG` to try a package.
  - *`vncserver`*: Arch's takes only a display and runs the systemd-style
    session, so `/usr/local/bin/vncserver` (bash, written in the `vnc` stage)
    takes Debian's arguments and runs `Xvnc` + `~/.config/tigervnc/xstartup`
    in the foreground. `_d_session_sh` knows both wrappers and X server names
    (`Xtigervnc`, `Xvnc`).
  - *Session bus*: Arch's `dbus-launch` has no X11 support, so xstartup's
    `dbus-launch --exit-with-session` kills its bus at once (stdin is
    `/dev/null`); each `vnc-session` does `eval "$(dbus-launch --sh-syntax)"`
    before `exec`ing the session (not `dbus-run-session`: the session process
    must carry the bus address for `d_exec -s`).
  - *noVNC/websockify* aren't packaged (AUR only): websockify from PyPI in
    `/opt/websockify` (venv), noVNC's release tarball in `/usr/share/novnc`;
    versions are build args.
  - *pasta*: `/usr/bin/pasta{,.avx2}` are hard links to `passt{,.avx2}`, not
    Arch's symlinks: a host with AppArmor profiles for both (Ubuntu) picks the
    profile by resolved path, and under passt's, pasta can't open the netns
    (nested containers: "Couldn't open network namespace … Permission denied").
  - *podman 6*: `nested.conf` has `[engine] env = ["TMPDIR=/tmp"]`, because
    `podman build` puts an overlay over the build context with its upper dir in
    `$TMPDIR`, and `/var/tmp` is on the instance's overlay root ("mounting an
    overlay over build context directory … invalid argument").
  - *`chromium`*: Arch's `chromium` package (Google Chrome is AUR-only) and
    the web fonts. No wrapper: `/usr/bin/chromium` is Arch's launcher, which
    reads `/etc/chromium-flags.conf` (`--no-sandbox --no-first-run
    --no-default-browser-check`); the build checks that `chromium --help`
    (stderr) lists the flag. The sandbox did work in a test without the flag;
    `--no-sandbox` is kept to match Chrome's stages. `ENV BROWSER=chromium`.
    `env.rc` treats the stage like `chrome` (`d_test`'s browser check uses
    `google-chrome` or else `chromium`; `d_screenshots` skips it);
    `d_chrome_bin=chromium d_chrome` for automation.
  - *`openbox`*: `openbox-session`, own `/etc/xdg/openbox/menu.xml` (the
    packaged one calls Debian's `x-terminal-emulator`; ours has Terminal, Chromium, Exit), an xterm from the
    system autostart, `scrot` for screenshots. Menu → Exit ends the session.
    No locker installed (`tests/lock.sh` passes).
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
- **Architectures**: Ubuntu and Debian build on amd64 and arm64 (the Chrome and
  OpenCode `.deb` URLs use `dpkg --print-architecture`, which is the image's,
  also in a cross build under emulation; upstream publishes both arches for
  OpenCode Desktop and CLI); Arch Linux is amd64 only (Docker Hub's
  `archlinux` has no arm64), so on arm64 (`uname -m` = `aarch64`) `env.rc` unsets
  its `d_bases`/`d_images` entries and `d_targets_archlinux`: no list has it, and
  `d_distro=archlinux` is refused. Google publishes official Linux arm64 builds of
  Chrome since 2026 (Canary first). The shared apt caches
  can serve both: `.deb` names carry the architecture. The user also runs
  instances on an arm64 machine (DGX Spark), so Claude Code may be running on
  arm64 for builds and tests there: check `uname -m` / `dpkg --print-architecture`
  before assuming amd64, and keep changes architecture-neutral.
- **Chrome** runs via the `/usr/local/bin/google-chrome-stable` wrapper
  (`--no-sandbox` etc.); `~/.config/chrome-flags.conf` does nothing on Ubuntu.
- **Chrome automation** uses the DevTools port from inside the instance
  (`d_chrome`): no published port, clients run there via `d_exec`/`podman exec -i`.
  It needs a profile other than the default (`--user-data-dir`): since Chrome 136
  `--remote-debugging-port` is ignored on `~/.config/google-chrome`.
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
  `$d_dir/<image name>N` (`u2604cc1`, `d13cc1`). When `d_run` runs nested (`$container` set) it's
  `<this instance>_N<letter>` (e.g. `cc2u_1d`, then `cc2u_1d_1u`), home
  `~/Containers/<that name>`, with no `--hostname`; the parent's name comes
  from `$D_NAME`, which `d_run` sets (nested instances share the hostname),
  falling back to `$HOSTNAME`. Ports: Ubuntu 6900+N (VNC) / 6080+N (noVNC),
  Debian 6950+N / 6130+N, chrome 7000+N / 6180+N, archlinux 7050+N / 6230+N,
  opencode 7150+N / 6330+N, so every distro's instance N can run at once. A distro
  can have its own prefix and letter (`d_name0s`, `d_letters`): opencode is `oc1u`,
  nested `<this instance>_oc1u`.
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
- **All of it in one go**: `source ./env.rc; [d_distro=debian] d_test N <stage>`
  (N unused, e.g. 1): builds, runs `<this instance>_N<letter>` on a new home, runs
  the checks below (ok/FAIL lines, non-zero status on a FAIL) and removes it again.
  Logs and the screenshot are in `/tmp/d_test/<instance>-<stage>.{build.log,log,png}`:
  Read the PNG. `d_test_keep=1` leaves the instance up for a closer look (then
  `d_rm -f N`). The steps by hand:
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
  Start GUI apps with `d_exec -s -d <app>` (DISPLAY is already set; plain
  `podman exec -d` has ambient caps and no session bus).
- **Root for experiments**: `podman exec -u root cc1u_1u sh -c 'apt-get update &&
  apt-get install -y …'` (try packages there before editing the Containerfile).
  `xdotool` (keys, clicks, window queries) is in every stage from `vnc` on. To query apt without an instance:
  `podman run --rm --user root u2604cc:chrome sh -c 'apt-get update -qq; apt-cache policy PKG'`.
- **Checks worth repeating** for any stage: `tests/tests.sh` inside it (4 ok);
  `podman inspect` and process environments contain no `VNC_PASSWORD`;
  `sudo -n true` is refused; noVNC answers on `http://127.0.0.1:<6080+N, Debian 6130+N>/vnc.html`
  and `[::1]`; ending the session stops the container (`podman ps -a` shows
  Exited, log says "vncserver exited") and `podman start` brings it back.
- **Clean up** what you started: `d_rm -f N` (= `podman rm -f -t 2 cc1u_1u`, retried
  because it sometimes fails once with an `openByHandleAt` error about exec
  sessions, then `podman unshare rm -rf ~/Containers/cc1u_1u`; plain `rm` fails on
  sub-ID-owned files). Check `podman ps -a`.
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
   lock request and the keyboard shortcut, not just the settings: `tests/lock.sh`
   (run by `d_test`); add the desktop's own lock command or D-Bus name to it.
5. Log out from the desktop must end the session (so the container stops), or
   provide a replacement and document it.
6. A screenshot tool that can save to a file without a dialog (`scrot` if
   the desktop's own can't), and a branch for it in `tests/screenshot.sh`.
7. `env.rc`: add to `d_targets_<distro>` and the `d_target` comment.
8. Docs: README (intro sentence, file table, Stages text and table, Screenshots
   item, `d_all` list), this file (intro, Files, design decisions), and
   `docs/<distro>/` (`d_distro=<distro> d_screenshots N <name>`, plus a section in `docs/README.md`).

## Gotchas met so far
- **Open**: `d_run_opts`' `--network=pasta:-T,5201,--map-gw` (order fixed for podman 4.9)
  lets `podman run` start, but iperf3 in the instance still can't reach the parent's
  port 5201. Not investigated yet.
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
- `SHELL` isn't set by podman (no login): `start.sh` exports the passwd entry's shell,
  so the whole session has it. Without it, apps that read `$SHELL` fell back to `sh`
  (OpenCode's terminal: dash, prompt `$ `). `podman exec` processes still lack it.
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
