# CLAUDE.md — vnc-desktop-podman

Rootless-podman images over TigerVNC/noVNC, with Google Chrome (Chromium on Arch), the
coding-agent CLI installers (Claude Code and others) and nested podman, in three layers:
- **distros** `ubuntu` (26.04), `debian` (13 trixie), `fedora` (45), `archlinux` (rolling):
  `container/deb/Containerfile` (shared by Ubuntu and Debian via `DISTRO`/`USER_FILES_GLOB`),
  `container/fedora/Containerfile`, `container/archlinux/Containerfile`, stages `base` → `vnc` → `browser`;
- **desktops** on a distro's `browser`: `container/<desktop>/Containerfile`, one stage per distro
  that has it: Ubuntu xfce, lxqt, gnome (Flashback), kde, mate, cinnamon; Debian gnome
  (Shell); Fedora xfce, lxqt; Arch openbox;
- **agent desktops** `<desktop>-<agent>` on a desktop: `container/<agent>/Containerfile`:
  `lxqt-opencode`, `lxqt-antigravity` (Ubuntu, Fedora), `gnome-opencode`,
  `gnome-antigravity`, `gnome-claude` (Ubuntu); an agent's `ubuntu` stage works on any
  Ubuntu desktop, as BASE is the desktop's image;
plus `devtools` (`container/chrome/`, Chrome automation on Ubuntu's `browser`).
Images are `vnc-desktop-<distro>:<target>-<version>`. Everything the images are built
from is under `container/`, with each agent desktop's README beside its Containerfile;
the top level has what the user works with (`env.rc`, `.env`, `README.md`, `docs/`,
`tests/`, `user_files/`, the `chrome/` helpers). See `README.md` for user-facing setup;
its "Agent desktops" section has a table of them.

## Files
Under `container/` (paths below without that prefix are relative to it, unless
they say otherwise):
- `deb/Containerfile` — shared by Ubuntu 26.04 and Debian 13 trixie (`ARG DISTRO`,
  `ARG USER_FILES_GLOB`), stages `base` (headless + nested rootless podman) → `vnc`
  (TigerVNC/noVNC, xterm session) → `browser` (Chrome + `cli-installers/`). The other
  distros' Containerfiles follow it. Package lists are kept **sorted**.
- `fedora/Containerfile` — Fedora 45 (`registry.fedoraproject.org/fedora:45`), same
  stages with dnf: see "Fedora" in the design decisions.
- `archlinux/Containerfile` — Arch Linux, same stages with pacman, Chromium in `browser`:
  see "Arch Linux" in the design decisions.
  The build context is the repo root for all, so they `COPY container/start.sh`,
  `container/nested-subids`, `container/vncserver-wrapper`, `container/cli-installers/`
  and `user_files/<distro>`; anything distro-specific goes in that distro's directory.
- `xfce/`, `lxqt/`, `gnome/`, `kde/`, `mate/`, `cinnamon/`, `openbox/` — one `Containerfile`
  each: `ARG BASE`, then one stage per distro named after it (`FROM ${BASE} AS ubuntu`),
  each the desktop's package `RUN` (with the distro's cache tail), a `RUN` writing
  `/usr/local/bin/vnc-session`, and its tweaks. `gnome/` has two different stages
  (`ubuntu`: Flashback, `debian`: Shell).
- `opencode/`, `antigravity/`, `claude/` — agent desktops, same pattern on a desktop, each
  with a `README.md` (keep the main README's agent desktop table in step).
  `opencode`: OpenCode Desktop (Electron `.deb` / `.rpm` from opencode.ai's "latest" URL,
  not GitHub's; arch `dpkg --print-architecture` for the `.deb`, `uname -m` for the
  `.rpm`; installs to `/opt/OpenCode`; shared `setup-opencode.sh` installs the
  `/usr/local/bin/ai.opencode` wrapper with `--no-sandbox --password-store=basic`, points
  both `.desktop` files at it, and links `opencode` to `/opt/OpenCode/resources/opencode-cli`).
  The app's own updater can't install a package without root: rebuild. The app copies its
  CLI into the home (`~/.config/ai.opencode.desktop/cli/<ver>/`, ~240 MB) and runs
  `opencode-cli serve` from there; no switch found to stop that. `opencode/README.md`.
  `antigravity`: one stage `app` (no package manager: the Electron tarball, version +
  execution id from the hub updater's `/releases` JSON, `ANTIGRAVITY_VERSION`/
  `ANTIGRAVITY_TGZ` override; `linux-x64`/`linux-arm` after `uname -m`; unpacked in
  `/opt/Antigravity`, build fails on a `not found` in `ldd`; wrapper with `--no-sandbox
  --password-store=basic`; our own `antigravity.desktop`; Python SDK `google-antigravity`
  in a user-owned `/opt/venv` with uv in `/opt/uv`, as in `chrome/`), and `ubuntu` and
  `fedora` are `FROM app`. `antigravity/README.md`.
  `claude`: stage `ubuntu` on `gnome` (see "`claude-desktop`" below). `claude/README.md`.
- `cli-installers/` — `install_claude`, `install_agy` (Google's `install.sh` →
  `~/.local/bin/agy`), `install_opencode` (opencode's build in `~/.opencode/bin`, first on
  PATH via `.bashrc`), `install_grok` (xAI's `https://x.ai/cli/install.sh` → `~/.grok/bin`,
  first on PATH via `.bashrc`; version argument or `GROK_CHANNEL`; sets `SHELL` from passwd
  when unset, as the installer picks the rc file by it; removes the installer's `agent`
  links), `install_t3code` (`https://t3.codes/install.sh` → `~/.t3/runtime/versions/<v>`
  (~500 MB) + `~/.local/bin/t3`; `T3CODE_VERSION`/`T3CODE_CHANNEL`; `t3` serves on
  127.0.0.1:3773 and prints a pairing URL; `t3 up`/`t3 service` need systemd). Every
  `browser` stage COPYs them to `/usr/local/bin`; run by the user, self-updating.
- `vncserver-wrapper` — `/usr/local/bin/vncserver` in every `vnc` stage (shadows the
  packaged one): `vncserver :N [-fg] [-localhost yes|no] [Xvnc options]`, runs
  `Xtigervnc` or `Xvnc` (whichever exists) and `~/.config/tigervnc/xstartup` in the
  foreground with the session environment Debian's perl `vncserver` sets
  (`XDG_SESSION_TYPE=x11`: Cinnamon's muffin quit without it), logs to stdout, exits when
  either ends.
- `start.sh` — entrypoint (PID 1's child under `--init`), shared by all images:
  first-boot seeding of the home volume and `nested-subids`; then, if the
  image has `vncserver`, runs `vncserver -fg` and `websockify` and exits when
  either does, so the container stops; otherwise (`base`) `exec sleep infinity`.
- `nested-subids` — `/usr/local/sbin`; `start.sh` runs it via `sudo` at every
  boot to fit subids and `newuidmap` caps to the container.
- `chrome/Containerfile` — `d_target=devtools` (stage `ubuntu`, on `vnc-desktop-ubuntu:browser-2604`,
  tagged `vnc-desktop-ubuntu:devtools-2604`): `google-chrome-canary` (wrapper like stable's),
  Openbox + xterm session, `scrot`, `socat`, `ffmpeg`, and global npm tools
  (`chrome-devtools-mcp`, `@playwright/mcp`, `puppeteer-core`, `playwright-core`,
  `lighthouse`; `NODE_PATH` set), and Python's `playwright` in a venv made with
  `uv`: `/opt/uv/bin/uv` and `/opt/venv`, both owned by the user and outside the
  home volume, venv first on `PATH` and `VIRTUAL_ENV` set, so the user can
  `uv pip install` without root. The top-level `chrome/search_screenshot.py` is a Python example
  (web search → PNG via the DevTools port). `install_chrome_devtools` (run by the
  user, like `install_claude`) copies `chrome-devtools-mcp`'s bundled skills to
  `~/.claude/skills`.
At the top level:
- `env.rc` — host-side bash helpers, `source`d from any cwd; defaults at the top,
  then `.env` (may override `d_dir`, `d_user`, `d_distro`, `d_target`, …), then derived values.
  `d_distro` ∈ `d_images` keys; `d_target` is one of `d_stages` (`base vnc browser`:
  `container/<distro>/Containerfile --target <stage>`), a desktop (`container/<dir>/Containerfile --target
  <distro>`, BASE `localhost/<image>:browser-<version>`; `d_dirs` maps `devtools` →
  `chrome`) or `<desktop>-<agent>` (`container/<agent>/Containerfile --target <distro>`, BASE
  `localhost/<image>:<desktop>-<version>`; agents in `d_agents`). Images are tagged
  `<image>:<target>-<version>` (`_d_tag`; versions in `d_versions`: ubuntu 2604, debian
  13, fedora 45, archlinux none, so `vnc-desktop-archlinux:openbox`). `_d_distro` works
  all that out at call time (`_d_cf`, `_d_stage`, `_d_parent`, `_d_base`, `_d_layer`,
  `_d_tag`), so
  `d_distro=fedora d_target=lxqt d_build` works; `d_build` builds `_d_parent` first, and
  `d_build`/`d_run` refuse a target that isn't in `d_targets_<distro>` (or a
  `<desktop>-<agent>` whose Containerfile has no `<distro>` stage). Functions: `d_0`,
  `d_build`, `d_build_fresh`, `d_select N`, `d_run_new`, `d_run`, `d_vnc`, `d_novnc`,
  `d_logs`, `d_all N [TARGET...]` (build + run every target on instances N, N+1, …, then
  `eval "$d_all_cmd"` in the background per instance, default `d_vnc`), `d_screenshots N
  [TARGET...]` (retake `docs/<distro>/<target>.png` on a throwaway instance N), `d_test N
  [TARGET...]` (build, run on a throwaway instance N, check, remove: see "Testing a
  change"), `d_exec [-s] [-d] CMD` (`podman exec` minus ambient caps; `-s`: with the
  session's D-Bus/XDG environment), `d_run_cmd [CMD...]` (default `bash`: throwaway
  `--rm -it` container `<name>-cmd` on instance N's image and home, beside a running
  instance: no `--replace`, no ports, no `start.sh`, no ambient caps), `d_rm [-f] [N]`
  (container **and home**; asks unless `-f`). `d_build` ends with a summary (time; per
  package step that ran: apt "downloaded/needed", `0 B/…` = all from the shared cache;
  dnf "downloaded/needed"; pacman "downloaded/installed") and labels the image
  `org.opencontainers.image.description` ("<distro>: <target text>" from
  `d_desc_distros`/`d_descs`, keyed `<distro>:<target>` or `<target>`; for an agent
  desktop "<agent text>; <desktop text>"; `d_description` overrides): **a new target or
  distro gets an entry there**. `_d_wait_ready` waits for password file + noVNC + a
  visible window; `_d_rm` is `d_rm` without asking.
- `.containerignore` — `d_build`'s context is the repo root; this allow-list sends only
  `LICENSE`, `container/{start.sh,nested-subids,vncserver-wrapper,cli-installers,opencode/setup-opencode.sh}`
  and `user_files`. **A new `COPY` source needs a `!` line here.**
- `chrome/env.rc` — sourced by `env.rc`: `d_chrome [URL...]` (Chrome on the
  instance's desktop with the DevTools port, 127.0.0.1:9222 inside the instance,
  profile `~/.config/chrome-automation`) and `d_chrome_mcp` (prints the `claude mcp
  add` line for `chrome-devtools-mcp` run in the instance via `podman exec -i`: the
  image's binary if there is one, else `npx`). `d_chrome_bin=google-chrome-canary d_chrome`
  for Canary, `d_chrome_bin=chromium` on Arch. `d_devtools CMD...` runs the
  `chrome-devtools` CLI (same tools as the MCP server; daemon in the instance, started on
  demand) in a `devtools` instance.
  Both get `_d_devtools_opts`: `--browserUrl`, no usage statistics, no CrUX,
  `--workspace=/home/<user>` (+ `d_devtools_opts`).
  `chrome/README.md` — the automation options compared, and what has been tried.
- `tests/tests.sh` — nested-podman checks, run inside an instance.
   `tests/test_env.sh` — fast stubbed-`podman` unit tests for `env.rc` and `chrome/env.rc`
  (also run in `.github/workflows/ci.yml` alongside `shellcheck`).
   `tests/screenshot.sh` — full-screen PNG of `:1` via `xfce4-screenshooter` / `screengrab` / `gnome-screenshot` / `spectacle` / `scrot`; copy it out
  with `podman cp` and look at it to check a desktop by script.
   `tests/lock.sh` — sends every lock request it knows (screensaver D-Bus names,
  desktops' lock commands, Super+L, Ctrl+Alt+L) and after each types into its own
  xterm with `xdotool` (XTEST, which a locker's grab would divert): FAIL if the
  text doesn't arrive. Needs the session bus (`d_exec -s`); throwaway instances only.
- `docs/` — `README.md` gallery with one screenshot per desktop on a fresh home
  (`docs/<distro>/<target>.png`); retake a desktop's picture when its initial look changes
  (`[d_distro=…] d_screenshots N <target>`). Taken by hand, not by `d_screenshots`:
  `archlinux/browser.png`, `antigravity/lxqt-nested.png` (the App in an instance, then named `ag1u`, and a nested
  `ag1u_ag1u` on arm64).
- `.env` — `export VNC_PASSWORD=…` and local settings such as `d_dir=…`
  (gitignored, never commit or print it). Usually absent inside an instance.

## Where you're probably running
Claude Code usually runs *inside* an instance (e.g. `vnc-desktop-ubuntu-lxqt-2604-6901`) with this repo on
the home volume. Every image has a nested rootless podman
for scratch containers, but it is *not* the host's podman, and the host paths
(`$d_dir`, the NFS apt cache) are not visible. When `$container` is set, `env.rc`
switches to nested paths (`d_dir=~/Containers`, instance N named `<this instance>_<image>-<tag>-<VNC port>` (e.g. `vnc-desktop-ubuntu-lxqt-2604-6901_vnc-desktop-debian-gnome-13-6951`) with home `~/Containers/<that name>`,
the instance's `/var/cache/apt-<distro>` cache mounts, no `--hostname`), so `d_build`/`d_run` here
build and run a nested instance in the nested podman, not a host one. Check things in the container directly (`/proc/1/environ`,
`mountpoint /var/cache/apt-ubuntu /var/cache/apt-debian /var/cache/apt-fedora`, `~/.config/tigervnc`) and test `env.rc`
changes with a stubbed `podman`, both ways (`container=` for host behaviour):
```bash
T=$(mktemp -d)   # d_run really creates the home dir and its passwd.init there
VNC_PASSWORD=x bash -c 'podman(){ echo "[podman $*]"; }; source ./env.rc; d_dir='$T'/n; d_select 1; d_run'
VNC_PASSWORD=x container= bash -c 'podman(){ echo "[podman $*]"; }; source ./env.rc; d_dir='$T'/h; d_select 1; d_run'
```
(Homes, names and ports are worked out at call time, so setting `d_dir` after
sourcing works; add `d_distro=debian d_target=gnome` to a command for Debian, and
`d_target=lxqt-opencode` etc. for an agent desktop. `d_run_new` loops
on `podman container exists`, so stub that to fail.)
The user builds, runs and pushes from the host. This clone has an `origin`
(GitHub), but don't push from here: commit locally and leave the push to the user.

## Design decisions (don't undo without asking)
- **Home is a volume** (`$d_dir/<instance name>` → `/home/ed`). Anything put in
  `/home/ed` at build time is hidden; per-user setup belongs in `start.sh`'s
  first-boot blocks (guarded by "file doesn't exist yet") or runs at runtime.
  The user's own files for new homes go in `user_files/<distro>/` at the top level
  (gitignored, may be absent; the user's, don't edit or print them): the base stage
  packs them into `/usr/local/share/user_files.tar` (`COPY LICENSE
  user_files/ubunt[u]`: the bracket makes it a glob that may match nothing; LICENSE is
  there because COPY fails when nothing matches), and `start.sh`
  unpacks it as the last step of the "no `~/.bashrc`" first-boot block, over
  `/etc/skel`'s files. The `D_NAME` `.bashrc` addition runs only when
  `$D_NAME` is set and the `.bashrc` doesn't mention it yet.
- **Claude Code** and the other agent CLIs are installed by the user at runtime via
  `install_claude` etc. (`cli-installers/`, in every `browser`; vendors' installers →
  the home, self-updating). Not baked into the image. Ubuntu's and Debian's `base`
  append a `~/.local/bin` PATH check to `/etc/skel/.bashrc` (the skel only has it in
  `.profile`, which a terminal's bash doesn't read), so a new home finds `claude`, `t3`
  and the like; Fedora's skel `.bashrc` has one already (the build checks). Small CLI
  tools the agents share (`fd-find`, `fzf`, `zstd`) are in `base`; `featherpad` is in
  `lxqt`. Grok and T3 Code are only installers, no agent desktop (decided).
- **Shared apt caches**, one per distro (same file names, different
  contents), NFS-shared between machines: host `$d_dir/apt-cache-<distro>/archives`
  (`apt-cache-ubuntu`, `apt-cache-debian`; Fedora's and Arch's under the same scheme, see
  there), or
  `d_aptcaches[<distro>]` from `.env`. Each image's apt keeps `.deb`s in
  `/var/cache/apt-<distro>` (`Dir::Cache::archives`, apt.conf.d
  `vnc-desktop-archives`; apt creates the dir when nothing's mounted).
  `d_build` mounts the distro's cache there; `d_run` mounts every distro's
  that exists (`/var/cache/apt-<distro>` for each), and nested, `env.rc` uses those
  mounts, so nested builds of any distro get their own cache. Desktops and agents use
  their distro's cache, with its tail. `docker-clean` is replaced by `docker-no-pkgcache`; every apt `RUN` ends
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
- **User, UID and GID** are build args (`USERID`, `USER_UID`, `USER_GID`; `d_build` passes
  `$d_user`, `id -u`, `id -g`), so keep-id lines up for any host user. Scripts use
  `$USERID` / `$SUDO_USER`, not a literal `ed`. `d_user` defaults to `${USER:-ed}` and
  `d_dir` to `${XDG_DATA_HOME:-$HOME/.local/share}/vnc-desktop` (override in `.env`).
- **Session comes from the image**: each image with a display installs
  `/usr/local/bin/vnc-session` (xterm / `startxfce4` / `startlxqt` / Flashback's parts / `startplasma-x11` / `mate-session` / `cinnamon-session-cinnamon2d` / `openbox-session`); the home's
  `xstartup` only runs it under `dbus-launch`, so a home works with any image.
  `vncserver` is the shared `vncserver-wrapper` in every distro (Debian/Ubuntu's perl
  one has its own options and logs, Arch's and Fedora's need systemd); `_d_session_sh`
  finds the session as the wrapper's child that isn't the X server.
- **Layers**: a desktop or agent `Containerfile` has one stage per distro, named after
  it, chosen with `--target <distro>`; a pair with no stage isn't supported (env.rc
  refuses it). A stage with nothing distro-specific is shared (`antigravity`: `FROM app
  AS ubuntu`). Agents and `devtools` have their own instances (names, homes, ports),
  keyed by the layer.
- **Nothing old is supported yet** (the user, 2026-11-24): no compatibility with older
  images, instance names or homes needs keeping; prefer the clean scheme.
- **LXQt without recommends** needs explicit `breeze-icon-theme`,
  `libxcb-cursor0`, `lxqt-menu-data`, `openbox`, `qt6-svg-plugins` on Ubuntu (see the
  `lxqt` stage comment); the default panel drops the `volume` plugin
  (`/etc/xdg/lxqt/panel.conf`, written on Ubuntu, edited in place on Fedora, whose
  `lxqt-panel` ships it there; no sound device, so it showed a red X). Check a
  new desktop with `tests/screenshot.sh`.
- **Ubuntu's `gnome` is GNOME Flashback**, not GNOME Shell: Shell 50 is Wayland-only and
  needs logind (tried with a mock logind + PipeWire + `--devkit`: it only
  half-started). No `gnome-session` either (needs systemd), so `vnc-session`
  starts `metacity`, `gnome-flashback` and `gnome-panel` itself and the session
  lasts as long as the panel; a menu entry (`vnc-logout.desktop`) stands in
  for Log Out. The panel layout is forced to `gnome-flashback` (Ubuntu's
  default wants an indicator applet that isn't installed). gnome-flashback's
  `screensaver` component is off (it locked after 5 idle minutes; no password).
- **Debian** (`debian/`): only Debian's default desktop, GNOME (`gnome/`, stage
  `debian`). Instances have their own names, homes and ports (see the instance
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
- **Fedora** (`fedora/`, Fedora 45): desktops `xfce`, `lxqt`, agents `lxqt-opencode`,
  `lxqt-antigravity`. Instances `vnc-desktop-fedora-<target>-45-<VNC port>`, ports 7350+N / 6530+N.
  - *Package cache*: dnf5 with `keepcache=True`, `cachedir` and `system_cachedir` (the
    one root uses) = `/var/cache/apt-fedora` in `dnf.conf`, so the shared
    `apt-cache-fedora` holds rpms **and repository metadata**; `install_weak_deps=False`
    (= `--no-install-recommends`). Every dnf `RUN` ends with `{ mountpoint -q
    /var/cache/apt-fedora || dnf clean all; }`.
  - Desktops are named packages, not Fedora's groups (`@xfce-desktop`, `@lxqt-desktop`
    bring SDDM, NetworkManager, abrt, …). No `xfce4-screensaver`, `light-locker` or
    `xfce4-power-manager`. `startlxqt` is in `lxqt-x11-session`, not `lxqt-session`.
    `xfce-polkit` (required by `xfce4-session`) has its autostart entry deleted: its
    agent fails without a system bus and showed an error dialog at every login.
  - *vnc*: `tigervnc-x11-server` (Xvnc; `vncpasswd` from `tigervnc-server-common`),
    `novnc`, `python3-websockify`, `dbus-x11` (with X11 support, unlike Arch's).
  - *browser*: Google's rpm `google-chrome-stable_current_$(uname -m).rpm` (x86_64 and
    aarch64 exist), same wrapper; no `x-www-browser` alternatives.
  - podman 6: `TMPDIR=/tmp` in `nested.conf` as on Arch; `pasta` made a hard link if
    it is a symlink.
- **Arch Linux** (`archlinux/`): stages `base`, `vnc`, `browser` (Chromium); desktop
  `openbox` (`openbox/`, stage `archlinux`); the shared `start.sh` and `nested-subids`
  run unchanged, so the image adapts to them:
  - *Package cache*: same scheme and names as apt's (`apt-cache-archlinux`,
    `/var/cache/apt-archlinux`, `d_aptcaches[archlinux]`), holding pacman's
    packages: `pacman.conf` gets `CacheDir = /var/cache/apt-archlinux/` and loses
    `DownloadUser` (it chowns its download dir to `alpm`, which a shared cache
    can't do). Every pacman `RUN` is `pacman -Syu --noconfirm --needed …` (never
    `-Sy`: no partial upgrades) with the tail `{ mountpoint -q
    /var/cache/apt-archlinux || rm -rf /var/cache/apt-archlinux/*; } && rm -rf
    /var/lib/pacman/sync/*`. So an instance has no sync databases: as root,
    `pacman -Syu --needed PKG` to try a package.
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
  - *`browser`*: Arch's `chromium` package (Google Chrome is AUR-only) and
    the web fonts. No wrapper: `/usr/bin/chromium` is Arch's launcher, which
    reads `/etc/chromium-flags.conf` (`--no-sandbox --no-first-run
    --no-default-browser-check`); the build checks that `chromium --help`
    (stderr) lists the flag. The sandbox did work in a test without the flag;
    `--no-sandbox` is kept to match Chrome's images. `ENV BROWSER=chromium`.
    `d_test`'s browser check uses `google-chrome` or else `chromium`;
    `d_chrome_bin=chromium d_chrome` for automation.
  - *`openbox`*: `openbox-session`, own `/etc/xdg/openbox/menu.xml` (the
    packaged one calls Debian's `x-terminal-emulator`; ours has Terminal, Chromium, Exit), an xterm from the
    system autostart, `scrot` for screenshots. Menu → Exit ends the session.
    No locker installed (`tests/lock.sh` passes).
- **`claude-desktop`** (the Claude desktop app) is only the agent desktop `gnome-claude`
  on Ubuntu (`claude/`, stage `ubuntu`), on purpose: it is still in beta, so don't add
  other pairs. It
  comes from Anthropic's apt repository: the Containerfile downloads the signing
  key (`https://downloads.claude.ai/keys/claude-code.asc`) and writes
  `claude-desktop.list` to the paths the package's own postinst uses, then
  `apt-get install` (with recommends, unlike the desktop package lists;
  `gnome-keyring` is named explicitly because the app needs it). Not the
  .deb-download pattern used for Chrome: the only known .deb URL is versioned.
  It stores secrets in
  the default keyring (gnome-keyring, D-Bus activated). A new home has none, and
  gnome-keyring's "choose a password" dialog left the app hanging, so the wrapper
  `/usr/local/bin/claude-desktop` (ahead of `/usr/bin`; menu entries pointed at it)
  writes a passwordless plain-text keyring
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
  **Any new desktop: check that the screen can't lock.**
- **Architectures**: Ubuntu, Debian and Fedora build on amd64 and arm64 (the Chrome and
  OpenCode `.deb` URLs use `dpkg --print-architecture`, the `.rpm` URLs and Antigravity
  `uname -m`, which are the image's, also in a cross build under emulation; upstream
  publishes both arches for OpenCode Desktop and CLI); Arch Linux is amd64 only (Docker Hub's
  `archlinux` has no arm64), so on arm64 (`uname -m` = `aarch64`) `env.rc` unsets
  its `d_bases`/`d_images` entries and `d_targets_archlinux`: no list has it, and
  `d_distro=archlinux` is refused. Google publishes official Linux arm64 builds of
  Chrome since 2026 (Canary first). The shared caches
  can serve both: package names carry the architecture. The user also runs
  instances on an arm64 machine (DGX Spark), so Claude Code may be running on
  arm64 for builds and tests there: check `uname -m` / `dpkg --print-architecture`
  before assuming amd64, and keep changes architecture-neutral.
- **Chrome** runs via the `/usr/local/bin/google-chrome-stable` wrapper
  (`--no-sandbox` etc.); `~/.config/chrome-flags.conf` does nothing on Ubuntu.
- **Chrome automation** uses the DevTools port from inside the instance
  (`d_chrome`): no published port, clients run there via `d_exec`/`podman exec -i`.
  It needs a profile other than the default (`--user-data-dir`): since Chrome 136
  `--remote-debugging-port` is ignored on `~/.config/google-chrome`.
- **Ports bind all interfaces** by default (trusted LAN); `d_bind=127.0.0.1` in `.env`
  restricts `d_run` to localhost for SSH-tunnel use.
- **Default `d_run_opts`** is `("-d" "--cap-add=NET_RAW")`; debug host-network flags
  (`--network=pasta:-T,5201,--map-gw`) are opt-in via `.env`.
- `PODMAN_USERNS=keep-id`; container user `ed` is UID 1001 by default, same as on the host.
- `label=disable` (not `:z`) on mounts.
- **Nested podman** (every image): `/etc/subuid`/`subgid` are `ed:1:1000` +
  `ed:1002:64534` (subgid also `ed:0:1`, below), because the outer rootless container only has UIDs 0–65535;
  `containers.conf.d/nested.conf` disables cgroups and uses file events (no
  systemd), and sets `utsns = "host"` (outer seccomp blocks `sethostname`).
  `newuidmap`/`newgidmap` use file caps, not setuid (setuid-root gets EPERM
  on `uid_map`). Those subids and caps are only build-time defaults:
  `nested-subids` rewrites the subids from `/proc/self/{uid,gid}_map` extents
  and re-applies the caps at every boot, so a desktop nested in an instance
  (`vnc-desktop-ubuntu-N_vnc-desktop-debian-M`) works too. `/etc/subgid` also gets `ed:0:1` (the
  instance's root group), so root in a nested build can write the shared apt
  cache's `partial/` (`_apt:root`, 700); podman sorts it to nested gid 1.
  `d_run` passes `/dev/fuse`,  `/dev/net/tun` and `unmask=/proc/*` (needed for nested `proc` mounts).
  Nested storage is in the instance's `~/.local/share/containers`, owned by mapped
  sub-IDs (delete it with `podman unshare rm -rf`, also from the host); ports a nested
  container publishes are reachable only inside the instance, so connect from there
  (`d_vnc`). `d_run` omits `--hostname` when `$container` is set (it wouldn't work).
  Without a `.env`, a nested desktop gets a copy of this instance's VNC password file.
  No seccomp or further relaxation: ask before adding any.
- Instance N (1-49) → `<image>-<tag>-<VNC port>`, the tag being `<target>[-<version>]`
  and the port worked out from N (`vnc-desktop-ubuntu-lxqt-2604-6901`,
  `vnc-desktop-fedora-lxqt-antigravity-45-7207`, `vnc-desktop-archlinux-openbox-7051`):
  the container, its hostname and its home `${d_homes0[<distro>]:-$d_dir}/<name>`. So
  each target has its own instance and home; ports are per distro or layer, so two
  targets of a distro on the same N clash (names ending alike), and `d_run_new` skips
  an N whose VNC port ends a container's or home's name (`_d_port_used`). The user
  still selects by N. When `d_run` runs nested (`$container` set) it's
  `<this instance>_<that name>` (e.g. `vnc-desktop-ubuntu-lxqt-2604-6902_vnc-desktop-debian-gnome-13-6951`, and
  so on one level deeper), home `~/Containers/<that name>`, with no `--hostname`; the
  parent's name comes from `$D_NAME`, which `d_run` sets (nested instances share the
  hostname), falling back to `$HOSTNAME`. Ports: Ubuntu 6900+N (VNC) / 6080+N (noVNC),
  Debian 6950+N / 6130+N, devtools 7000+N / 6180+N, archlinux 7050+N / 6230+N,
  opencode 7150+N / 6330+N, antigravity 7200+N / 6380+N, fedora 7350+N / 6530+N,
  claude 7400+N / 6580+N, so every distro's instance N can run at once (7100/6280:
  the `research` branch's omarchy; 7250/6430 and 7300/6480 were grok's and t3code's).
  The same layer on two distros shares its ports. `d_select N` keeps only N;
  `_d_names` works out name, home and ports from the current `d_distro` and
  `d_target` in every function that needs them (via `_d_need_instance`), so
  `d_select 1; d_distro=debian d_target=gnome d_run` is `vnc-desktop-debian-gnome-13-6951`.

## Conventions
- `env.rc`: build podman commands as bash arrays, `echo` then run; quote
  expansions; functions that need an instance call `_d_need_instance`.
- `start.sh` runs under `set -e`: make first-boot steps idempotent and
  non-failing on re-run.
- Update README when a change is user-visible.
- Commit only when asked, directly on `main` (no feature branches; the user
  usually tries a change on the host first, then says "commit this"). Never
  push. Desktops and agents are directories with a stage per distro (not branches).

## Testing a change from inside an instance
You are `ed` with **no root** here (`sudo` only runs `nested-subids`), and the
image has no package lists. Everything below uses the nested podman.
- **All of it in one go**: `source ./env.rc; [d_distro=…] d_test N <target>`
  (N unused, e.g. 1): builds, runs `<this instance>_<image>-N` on a new home, runs
  the checks below (ok/FAIL lines, non-zero status on a FAIL) and removes it again.
  Logs and the screenshot are in `/tmp/d_test/<instance>-<target>.{build.log,log,png}`:
  Read the PNG. `d_test_keep=1` leaves the instance up for a closer look (then
  `d_rm -f N`). The steps by hand:
- **Build**: `source ./env.rc; [d_distro=…] d_target=<target> d_build > LOG 2>&1` — takes
  minutes (use a long timeout, log to a file, check the exit status). Changing
  `start.sh` or anything in `base` rebuilds every later stage and all desktops on it.
- **Run a throwaway instance**: `d_run_new` (picks a free number), then
  `[d_distro=…] d_target=<target> d_run`. It is `<this instance>_<image>-<tag>-<VNC port>`, e.g. `vnc-desktop-ubuntu-lxqt-2604-6920_vnc-desktop-ubuntu-xfce-2604-6901` (`$d_name`
  after `d_select`), with home `~/Containers/<that>` (`$d_home`), which is directly
  readable here: copy files in and out with plain `cp` (e.g. `cp -r tests "$d_home"/`),
  no `podman cp`
  needed. No `.env` is needed: it gets a copy of this instance's VNC password.
- **Look at it**: `podman exec "$d_name" /home/ed/tests/screenshot.sh /home/ed/s.png`,
  then Read `$d_home/s.png`. Give a desktop 15-40 s to come up first.
  Start GUI apps with `d_exec -s -d <app>` (DISPLAY is already set; plain
  `podman exec -d` has ambient caps and no session bus).
- **Root for experiments**: `podman exec -u root "$d_name" sh -c 'apt-get update &&
  apt-get install -y …'` (Fedora: `dnf install -y …`; try packages there before editing
  the Containerfile). `xdotool` (keys, clicks, window queries) is in every image from
  `vnc` on. To query packages without an instance:
  `podman run --rm --user root vnc-desktop-ubuntu:browser-2604 sh -c 'apt-get update -qq; apt-cache policy PKG'`,
  or `podman run --rm --user root -v /var/cache/apt-fedora:/var/cache/apt-fedora
  --security-opt label=disable registry.fedoraproject.org/fedora:45 dnf repoquery
  --setopt=system_cachedir=/var/cache/apt-fedora PKG`.
- **Checks worth repeating** for any image: `tests/tests.sh` inside it (4 ok);
  `podman inspect` and process environments contain no `VNC_PASSWORD`;
  `sudo -n true` is refused; noVNC answers on `http://127.0.0.1:<6080+N, Debian 6130+N, …>/vnc.html`
  and `[::1]`; ending the session stops the container (`podman ps -a` shows
  Exited, log says "vncserver exited") and `podman start` brings it back.
- **Clean up** what you started: `d_rm -f N` (= `podman rm -f -t 2 "$d_name"`, retried
  because it sometimes fails once with an `openByHandleAt` error about exec
  sessions, then `podman unshare rm -rf "$d_home"`; plain `rm` fails on
  sub-ID-owned files). Check `podman ps -a`.
- **Not testable here**: the real host (NFS apt cache, host paths, other UIDs).
  Say so instead of guessing; the user tests on the host.

## Adding a desktop (checklist)
1. `container/<desktop>/Containerfile` (new directory, `ARG BASE=localhost/vnc-desktop-<distro>:browser-<version>`
   and a header comment listing its stages, like `xfce/`), or a new stage in an existing
   one: `FROM ${BASE} AS <distro>`, `USER root`, `ARG USERID USER_UID`, one sorted package
   `RUN` with that distro's cache tail, a `RUN` writing `/usr/local/bin/vnc-session`,
   then `USER ${USERID}`. An agent desktop is the same in `container/<agent>/Containerfile` on a
   desktop (and the agent goes in `d_agents`, with ports and
   `d_descs`).
2. Find out what works before writing it: is there an X11 session at all
   (GNOME Shell: no), does its session manager need systemd/logind (start
   the parts by hand if so, as in `gnome`)? Try it in a throwaway instance.
3. Look at a screenshot of a **fresh home**. Ubuntu's default panel layouts
   often reference applets that `--no-install-recommends` leaves out (empty
   panel, "Error" boxes, blank icons; Fedora's without weak deps likewise): fix with a gsettings override in
   `/usr/share/glib-2.0/schemas/99_vnc-desktop.gschema.override` +
   `glib-compile-schemas --strict`, as in `gnome`/`mate`/`cinnamon`.
4. **Screen lock must be impossible** (no password to unlock): test an explicit
   lock request and the keyboard shortcut, not just the settings: `tests/lock.sh`
   (run by `d_test`); add the desktop's own lock command or D-Bus name to it.
5. Log out from the desktop must end the session (so the container stops), or
   provide a replacement and document it.
6. A screenshot tool that can save to a file without a dialog (`scrot` if
   the desktop's own can't), and a branch for it in `tests/screenshot.sh`.
7. `env.rc`: add to `d_targets_<distro>`, the `d_target` comment and `d_descs`.
8. A new directory with a `COPY` source: a `!` line in `.containerignore` (a desktop's
   `Containerfile` alone needs none: it's passed with `-f`).
9. Docs: README (intro table, file table, Images table and Desktops text, `d_all` list),
   this file (intro, Files, design decisions), and `docs/<distro>/`
   (`d_distro=<distro> d_screenshots N <name>`, plus a section in `docs/README.md`).
   An agent desktop also gets `container/<agent>/README.md` and a row in the README's
   "Agent desktops" table.

## Gotchas met so far
- **Open**: with optional debug `d_run_opts` `--network=pasta:-T,5201,--map-gw` (order
  fixed for podman 4.9), `podman run` starts, but iperf3 in the instance didn't reach the
  parent's port 5201 when tested. Note: in `pasta`, `-T 5201` forwards container loopback
  `127.0.0.1:5201` → host `127.0.0.1:5201`, whereas `--map-gw` routes to the host's
  non-loopback gateway IP. Not re-tested yet.
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
