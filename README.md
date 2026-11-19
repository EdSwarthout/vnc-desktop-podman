# vnc-desktop-podman — Desktops over VNC in rootless podman, with Chrome, and nested podman

A rootless-podman container that runs an XFCE, LXQt, GNOME Flashback, KDE Plasma, MATE or Cinnamon desktop
on Ubuntu 26.04, GNOME on Debian 13 (trixie), or Openbox on Arch Linux, over VNC/noVNC,
with Google Chrome (Chromium on Arch), Claude Code and nested rootless podman. Smaller stages
(headless, or VNC with just an xterm) are built from the same `Containerfile` (`ubuntu/`, `debian/` or `archlinux/`).
Each instance keeps its home directory on the host, so settings, browser profile
and the Claude install survive rebuilds.

Why use it: [A full Linux desktop for your AI agent, in a rootless container](docs/Advantages-article.md).

| File            | Purpose                                                       |
|-----------------|---------------------------------------------------------------|
| `ubuntu/Containerfile` | Ubuntu image stages `base` → `vnc` → `chrome` → `xfce` / `lxqt` / `gnome` / `kde` / `mate` / `cinnamon` (see [Stages](#stages)) |
| `debian/Containerfile` | Debian image stages `base` → `vnc` → `chrome` → `gnome` (see [Debian](#debian)) |
| `archlinux/Containerfile` | Arch Linux image stages `base` → `vnc` → `chromium` → `openbox` (see [Arch Linux](#arch-linux)) |
| `start.sh`      | Container entrypoint (all distros): first-boot setup, starts the VNC session if the stage has one |
| `nested-subids` | Fits nested podman's sub-IDs to the container at boot (all distros) |
| `tests/`        | `tests.sh` (nested podman checks), `screenshot.sh` (desktop screenshot), `lock.sh` (the screen can't be locked) |
| `docs/`         | [Screenshots](docs/README.md) of each stage's desktop; [article](docs/Advantages-article.md) on the advantages |
| `env.rc`        | Shell helpers (`d_build`, `d_select`, `d_run`, `d_vnc`, `d_novnc`, `d_exec`, `d_test`, `d_rm`, …)    |
| `opencode/`     | [OpenCode](https://opencode.ai): `Containerfile` (`d_distro=opencode`: Ubuntu's `lxqt` stage + OpenCode Desktop and the `opencode` terminal UI, stage `lxqt`) and a [README](opencode/README.md) |
| `.containerignore` | Keeps `d_build`'s context (the repo root) to the files the Containerfiles copy |
| `chrome/`       | Chrome automation: `Containerfile` (`d_distro=chrome`: Ubuntu's `chrome` stage + Chrome Canary and browser tools, stage `canary`), `env.rc` (`d_chrome`, `d_chrome_mcp`, sourced by the top-level `env.rc`) and a [README](chrome/README.md) of the options |
| `.env`          | Your VNC password and local settings (not in git)             |
| `<distro>/user_files/` | Your own files for new homes, e.g. a `.bashrc` (not in git; see [Run an instance](#run-an-instance)) |

## Requirements

- Linux host, amd64 or arm64 (Ubuntu and Debian; Arch Linux is amd64 only, and
  `env.rc` leaves it out on arm64), `podman` (rootless).
- Optional: `vncviewer` (TigerVNC) on the host for `d_vnc`; otherwise any
  browser works via noVNC.
- The container user is named `ed` (`d_user`) and gets the UID of whoever runs
  `d_build`. `env.rc` sets `PODMAN_USERNS=keep-id`, which maps your host user
  to that same UID in the container, so it owns the home dir. Build on each
  machine (or as each user) whose UID differs. For another name, set
  `d_user=…` in `.env` (step 2).

## One-time setup

1. **Choose `d_dir`**, a host directory for container data, and set it in
   `.env` (step 2) rather than editing the default in `env.rc`.
   Everything else is derived from it:
   - `$d_dir/u2604cc` (Ubuntu), `$d_dir/d13cc` (Debian) and `$d_dir/archcc` (Arch Linux) — prefixes for
     each instance's home dir (Ubuntu instance 1 → `$d_dir/u2604cc1`); set
     `d_homes0[debian]=…` etc. in `.env` to put them elsewhere.
   - `$d_dir/apt-cache-ubuntu/archives` and `$d_dir/apt-cache-debian/archives` — downloaded `.deb`s, one cache per distro, meant to be shared
     between machines over NFS so packages are downloaded once. That's why
     they're mounted directories rather than a podman build cache, which stays
     local to one machine. `d_build` mounts the distro's cache on
     `/var/cache/apt-<distro>` (where the images' apt keeps its `.deb`s);
     `d_run` mounts both, on `/var/cache/apt-ubuntu` and
     `/var/cache/apt-debian`, so a build inside an instance uses the right one
     for either distro (a missing one is skipped with a note). Create them:
     `mkdir -p "$d_dir"/apt-cache-{ubuntu,debian}/archives` (and
     `apt-cache-archlinux/archives` for Arch Linux: same scheme and names, though
     it holds pacman's packages; see [Arch Linux](#arch-linux)). On the NFS server,
     export these `archives` directories, e.g.:
     ```
     /mnt/hwd23data/sw/docker/apt-cache-ubuntu/archives hwd4(rw,sync,all_squash,anonuid=1001,anongid=1001)
     /mnt/hwd23data/sw/docker/apt-cache-debian/archives hwd4(rw,sync,all_squash,anonuid=1001,anongid=1001)
     ```
     On a client, mount them at the same paths under that client's `$d_dir`,
     or set `d_aptcaches[ubuntu]=…` / `d_aptcaches[debian]=…` in `.env`.

2. **Create `.env`** next to `env.rc` with the VNC password (VNC only uses
   the first 8 characters) and your `d_dir`. `env.rc` sources it, so it can
   override any of the defaults at the top of `env.rc` (`d_dir`, `d_user`,
   `d_distro`, `d_target`, `d_aptcaches`, `d_homes0`):
   ```bash
   cat > .env <<'EOF'
   export VNC_PASSWORD=yourpass
   d_dir=/srv/containers
   EOF
   chmod 600 .env
   ```

3. **Load the helpers** (from any directory):
   ```bash
   source /path/to/vnc-desktop-podman/env.rc
   ```

4. **Pull the base image and build** (from any directory):
   ```bash
   d_0        # podman pull docker.io/library/ubuntu:26.04
   d_build    # podman build -t u2604cc:$d_target -f ubuntu/Containerfile --target $d_target …
   ```
   `d_target` in `env.rc` picks the stage (default `xfce`); see below. To build
   or run another one without editing `env.rc`: `d_target=lxqt d_build`,
   `d_target=lxqt d_run`. For Debian, see [Debian](#debian); for Arch Linux, [Arch Linux](#arch-linux).

## Stages

These are Ubuntu's stages (`ubuntu/Containerfile`, the default `d_distro`);
for Debian's see [Debian](#debian). Each stage builds on the one before; `xfce`, `lxqt`, `gnome`, `kde`, `mate` and `cinnamon` each build on `chrome`.
Every stage is runnable with `d_run`, and the image is tagged `u2604cc:<stage>`,
so building one doesn't replace another.

| Stage    | Adds                                                        | Session        |
|----------|-------------------------------------------------------------|----------------|
| `base`   | Ubuntu, network/debug and development tools (compilers, Python, Node, `gh`, …), editors, nested rootless podman, `install_claude` | none: headless, use `podman exec -it ccNu bash` |
| `vnc`    | TigerVNC server/viewer, noVNC                               | `xterm`        |
| `chrome` | Google Chrome (`--no-sandbox` wrapper), fonts (incl. CJK, emoji) | `xterm`        |
| `xfce`   | XFCE, `xfce4-screenshooter`                                 | XFCE           |
| `lxqt`   | LXQt with openbox, `screengrab`                             | LXQt           |
| `gnome`  | GNOME Flashback (gnome-panel, metacity, nautilus), `gnome-terminal`, `gnome-screenshot`, the Claude desktop app (`claude-desktop`) | GNOME Flashback |
| `kde`    | KDE Plasma 6 (X11 session, `kwin-x11`), Dolphin, Konsole, System Settings, `spectacle` | Plasma |
| `mate`   | MATE (mate-panel, marco, caja), `mate-terminal`, `scrot`    | MATE           |
| `cinnamon` | Cinnamon (software-rendering session), Nemo, `gnome-terminal`, `scrot` | Cinnamon |

`gnome` is GNOME Flashback, GNOME's classic X11 desktop, not GNOME Shell: the
GNOME Shell in Ubuntu 26.04 is Wayland-only and needs systemd-logind, so it
can't run as a session on the VNC X server. There is no `gnome-session`
either, so the user menu's **Log Out** does nothing: to end the session (and
stop the container) use **Applications → System Tools → Log Out (stop the
container)**, or `podman stop`. Screen locking is switched off (see `kde`).

`gnome` also has the Claude desktop app (`claude-desktop`, from Anthropic's apt
repository). It is only available in the `gnome` stage: the app is still in
beta, so the other desktop stages don't include it. It keeps its secrets in the GNOME keyring, so the session gives a
new home a default keyring without a password: nothing asks for one at the
app's first start. Secrets in it are not encrypted, only protected by the
home's file permissions. A home that already has a default keyring keeps it.

`kde` runs Plasma's X11 session (`startplasma-x11`). Locking the screen is
disabled, both the idle timer and by hand, because the user has no password to
unlock it with. It is the largest image, about 0.8 GB more than `chrome`.

`cinnamon` runs Cinnamon's software-rendering session (`cinnamon2d`), as there
is no GPU behind the VNC display. Its screensaver is not run at all, for the
same reason as in `kde`: it would lock the screen with no password to unlock it.

[`docs/`](docs/README.md) has a screenshot of each desktop as it first comes up.

A home dir works with any stage: the session comes from the image
(`/usr/local/bin/vnc-session`), not the home.

### Debian

`debian/Containerfile` builds Debian 13 (trixie) the same way, with Debian's
default desktop only: stages `base`, `vnc` and `chrome` (as in Ubuntu) and
`gnome`. Its images are tagged `d13cc:<stage>`. Select it with `d_distro`,
per command or in `.env` (together with a Debian stage as `d_target`, as the
default, `xfce`, is Ubuntu-only):
```bash
d_distro=debian d_0                      # podman pull docker.io/library/debian:trixie
d_distro=debian d_target=gnome d_build   # d13cc:gnome
d_select 5
d_distro=debian d_target=gnome d_run     # cc5d, home $d_dir/d13cc5
```
Debian instances have their own names, homes and ports (see [Run an
instance](#run-an-instance)), so Debian and Ubuntu instance 5 can run side by
side. Its `.deb`s go to their own cache,
`$d_dir/apt-cache-debian/archives` (create and NFS-export it like Ubuntu's, `$d_dir/apt-cache-ubuntu/archives`),
because both distros have files with the same name but different contents.

Debian's `gnome` is **GNOME Shell**, unlike Ubuntu's: GNOME 48 still has an X11
session. It starts without systemd, given a stand-in system D-Bus (with no
services on it, so GNOME logs warnings about logind, polkit, UPower etc.).
**Power Off → Log Out…** in the top-right menu ends the session and stops the
container (shown although there's only one user). Screen locking is impossible (no screen
shield without GDM; locking and idle blanking are also off in the settings).
The dash has Chrome, Files and Terminal; no Claude desktop app.

### Arch Linux

`archlinux/Containerfile` builds Arch Linux (rolling) the same way: stages
`base` and `vnc` (as in Ubuntu and Debian), `chromium` and `openbox`, a bare
window manager. `chromium` takes the place of `chrome`: Google Chrome isn't in
Arch's repositories, Chromium is. Images are tagged `archcc:<stage>`:
```bash
mkdir -p "$d_dir"/apt-cache-archlinux/archives   # once: d_build needs it
d_distro=archlinux d_0                        # podman pull docker.io/library/archlinux:latest
d_distro=archlinux d_target=openbox d_build   # archcc:openbox
d_select 5
d_distro=archlinux d_target=openbox d_run     # cc5a, home $d_dir/archcc5
```
Its package cache, `$d_dir/apt-cache-archlinux/archives`, works like the apt
caches and is named like them, but holds pacman's packages (the image's pacman
has `CacheDir = /var/cache/apt-archlinux/`). An instance created before this
cache directory existed doesn't have it mounted, so `d_build` for Arch inside
it fails until the instance is recreated with `d_run` (or
`d_aptcaches[archlinux]=…` points somewhere else).

`openbox` starts with one xterm on an empty background. Right-click the
background for the menu: **Terminal**, **Chromium**, the window list, and **Exit**, which
ends the session and stops the container. There is no panel and no screen
locker. A `~/.config/openbox/menu.xml` of your own replaces the image's menu;
a `~/.config/openbox/autostart` runs in addition to the image's.

Chromium (stage `chromium` and up) runs with `--no-sandbox`, as Chrome does in
the other images; the flags are in `/etc/chromium-flags.conf`, which Arch's
launcher reads, so there is no wrapper script. For automation, name the browser:
`d_chrome_bin=chromium d_chrome` (profile `~/.config/chromium-automation`);
see [chrome/README.md](chrome/README.md).

Differences from the Debian-based images, all handled in the image: Arch's
`vncserver` only works with systemd, so `/usr/local/bin/vncserver` stands in
for Debian's wrapper; noVNC and websockify aren't packaged, so they come from
noVNC's release tarball and PyPI (`NOVNC_VERSION`, `WEBSOCKIFY_VERSION` build
args); `pasta` is a hard link instead of Arch's symlink, as a host with
AppArmor profiles for passt and pasta (Ubuntu) otherwise confines it with the
wrong one and nested containers get no network.

## Run an instance

Instances are numbered 1-49, separately per distro. On the host, instance N
is named `ccN` plus the first letter of `d_distro`, uses home `<prefix>N`, and
publishes these ports (nested instances, run inside an instance, are named
differently; see item 4 of "Inside the container"):

| Distro | Instance | Container name | Home                | VNC port (host) | noVNC port (host) |
|--------|----------|----------------|---------------------|-----------------|-------------------|
| ubuntu | 1        | `cc1u`         | `$d_dir/u2604cc1`   | 6901            | 6081              |
| ubuntu | N        | `ccNu`         | `$d_dir/u2604ccN`   | 6900+N          | 6080+N            |
| debian | 1        | `cc1d`         | `$d_dir/d13cc1`     | 6951            | 6131              |
| debian | N        | `ccNd`         | `$d_dir/d13ccN`     | 6950+N          | 6130+N            |
| archlinux | 1     | `cc1a`         | `$d_dir/archcc1`    | 7051            | 6231              |
| archlinux | N     | `ccNa`         | `$d_dir/archccN`    | 7050+N          | 6230+N            |
| opencode | N      | `ocNu`         | `$d_dir/u2604opencodeN` | 7150+N      | 6330+N            |

`d_select N` only picks the number: the name, home and ports follow
`d_distro` at the time of each command, so after `d_select 1`,
`d_distro=debian d_run` runs `cc1d`.

Instances created before the names had the distro letter are called `ccN`:
stop or remove such an instance (`podman rm -f ccN`) and `d_run` it again,
which creates `ccNu` with the same home and ports.

```bash
d_select 1     # or d_run_new: the next number with no container and no home dir yet
d_run          # creates the home dir and starts (or replaces) the container
```

The VNC password never goes into the container's environment (where it would
show in `podman inspect` and be inherited by everything on the desktop). While
the home has no `~/.config/tigervnc/passwd`, `d_run` writes `$VNC_PASSWORD` to
`passwd.init` next to it (mode 600) and refuses to start without one; on first
start `start.sh` turns that into `passwd` and deletes it. After that the stored
password is used. (An instance created by an older `d_run` still has
`VNC_PASSWORD` in its environment: `d_run` it again once.) `start.sh` also
writes an `xstartup` that runs the stage's session (an `xstartup` written by
older versions, which always started XFCE, is replaced; a customised one is
kept).

`d_run` uses `--replace`, so running it again restarts the instance from the
current image; the home dir is kept.

**Your own files in new homes:** put them in `ubuntu/user_files/`,
`debian/user_files/` or `archlinux/user_files/` (gitignored), laid out as in the home, e.g. `.bashrc`,
`.bash_aliases`, `Downloads/…`, and `d_build`. The build packs them into the
image (`/usr/local/share/user_files.tar`; changing them rebuilds every stage),
and on a new home's first boot `start.sh` unpacks them, over the `/etc/skel`
defaults. Existing homes are not touched, and later edits in the home are kept.
They are in the image, so leave out secrets if you share it. A `.bashrc` of your
own should keep `start.sh`'s additions (the `~/.local/bin` PATH lines, and the
`D_NAME` prompt lines for nested instances): copy them from a home it set up.

Instances use the host's timezone (`--tz=local`); a nested one gets its parent
instance's.

The container stops if the VNC server or websockify exits — including when you
**Log Out** of the desktop (or exit the `xterm` in `vnc`/`chrome`; for Ubuntu's `gnome` see [Stages](#stages)). `podman start ccNu` brings it back; `podman logs ccNu` shows
which one exited.

## Connect to the desktop

- **Browser (noVNC):** `d_novnc` opens the selected instance's page in your
  default browser (`xdg-open`); from another machine it's
  `http://<host>:6081/vnc.html` for Ubuntu instance 1 (see the table above). Then
  enter the VNC password.
- **VNC client:** `d_vnc` runs `vncviewer` against the selected instance using
  its stored password file. From another machine, point a VNC client at
  `<host>:6901` (Ubuntu instance 1).

> The ports are published on all interfaces and VNC/noVNC traffic is
> unencrypted. Use this only on a trusted LAN behind a firewall, or change
> `d_run` to bind `127.0.0.1:` and use an SSH tunnel.

## Inside the container

1. **Install Claude Code** (once per instance; it lives in the home dir and
   updates itself):
   ```bash
   install_claude     # native installer → ~/.local/bin/claude
   claude
   ```

2. **Set your git identity** (once per instance):
   ```bash
   git config --global user.name  "Your Name"
   git config --global user.email "you@example.com"
   ```

3. **Chrome** (stage `chrome` and up) is in the menu and is the default web
   browser (XFCE's and `xdg-open`'s). It's wrapped to run with `--no-sandbox`
   (needed in the container), which is why Chrome shows an "unsupported
   command-line flag" bar.

4. **Containers inside an instance** (every stage): rootless `podman run`,
   `podman build` etc. work inside the instance. This is a separate podman, not
   the host's: its images and containers live in `~/.local/share/containers`
   in this instance's home dir, it can't see the host's images, and ports it
   publishes are reachable only from inside the instance.

   **Testing a change in a nested desktop.** `env.rc` works inside an instance
   too, so you (or Claude Code running there) can build this image and run it
   as a desktop inside the desktop, without touching the host's instances:
   ```bash
   cd <your clone of this repo>
   source ./env.rc
   d_target=gnome d_build     # build the stage you changed (takes minutes)
   d_run_new                  # pick a free instance number; prints its name
   d_target=gnome d_run       # start it with a new home
   d_vnc                      # look at it (or tests/screenshot.sh, item 5)
   ```
   Inside instance `cc3u`, nested instance N is named `cc3u_N` plus the
   distro letter (`cc3u_1u`, `cc3u_1d`) and its home is `~/Containers/cc3u_1u`,
   a plain directory you can read and copy files into.
   It shows that name in its VNC title and shell prompt, though `hostname`
   still says `cc3u`. It uses the same VNC password as this instance. To check
   that nested podman itself works, run `tests/tests.sh` (ok/FAIL per check).
   Remove a nested instance when you're done:
   ```bash
   podman rm -f -t 2 cc3u_1u
   podman unshare rm -rf ~/Containers/cc3u_1u    # plain rm can't delete all of it
   ```
   Nested instances count against this instance's limit on processes and
   threads (`d_pids_limit` in `env.rc`, 16384; `cat /sys/fs/cgroup/pids.max`
   shows it). An instance created before that setting has podman's 2048, which
   several nested desktops use up: apps then fail to start with "Resource
   temporarily unavailable". Recreate it from the host with `d_run` (the home
   is kept) to get the higher limit.
   The same `podman unshare rm -rf` is needed on the host to delete an
   instance's `.local/share/containers`. If `start.sh` warns at boot about
   older nested storage, run `podman system reset` once as it says. How the
   nesting is set up is described in `CLAUDE.md`.

5. **Screenshots** (`xfce`, `lxqt`, `gnome`, `kde`, `mate`, `cinnamon`): `tests/screenshot.sh [FILE.png]` saves a
   full-screen PNG of the desktop and prints its path.

**No root inside.** The image is meant to carry everything needed: `ed` has no
general `sudo` (the one exception is the boot-time `nested-subids`, which
`start.sh` runs). To add a package, put it in the `<distro>/Containerfile` (`base`
stage list) and `d_build`, then `d_run`. For a one-off as root, from the host:
`podman exec -u root ccNu apt-get update` / `… apt-get install -y PKG` (lost
when the container is replaced). Per-user tools need no root: `pip` in a
`python3 -m venv`, `npm install` in a project or with `--prefix ~/.local`,
and containers in the nested podman.

## Day-to-day

In a new shell, `source env.rc` and `d_select N` before using `d_run`/`d_vnc`/`d_novnc`
(they refuse to run with no instance selected).

```bash
podman ps                  # running instances
podman logs cc1u           # entrypoint / VNC / websockify output
podman stop cc1u           # stop
podman start cc1u          # start again (same container)
podman exec -it cc1ubash   # shell without the desktop
```

**Change the VNC password:** delete `<home>/.config/tigervnc/passwd` on
the host, update `.env`, `source env.rc`, then `d_run` again — or run
`vncpasswd` inside the container and restart it.

**Try every stage at once:** `d_all N` builds each stage of `$d_distro` (Ubuntu: `base vnc chrome
xfce lxqt gnome kde mate cinnamon`) and runs it on instance N, N+1, …, opening a `d_vnc` viewer in
the background for each one with a desktop (log in `/tmp/d_all-<name>.log`).
`d_all 11 xfce lxqt` limits it to those stages. N is required, because
`d_run` replaces whatever instance has that number.
What runs once each desktop is up is `$d_all_cmd` (default `d_vnc`): set it in
`.env` or per command to any shell command, which runs with that instance
selected (`$d_name`, `$d_home`, `$d_target`), or to empty for nothing:
```bash
d_all_cmd=d_novnc d_all 11 xfce lxqt                  # browser instead
d_all_cmd='podman logs "$d_name"' d_all 11 gnome      # save each boot log
d_all_cmd= d_all 11                                   # just build and run
```

**Retake the screenshots in `docs/`:** `d_screenshots N [STAGE...]` builds each
desktop stage, runs it on a new home as instance N (which must be unused; it is
removed again afterwards) and saves `docs/<distro>/<stage>.png`.

**Test a stage:** `d_test N [STAGE...]` builds each stage (default: all of
`$d_distro`), runs it on a new home as instance N (which must be unused; it is
removed again afterwards, unless `d_test_keep=1`) and prints `ok`/`FAIL` per check:
the instance comes up, nested podman works (`tests/tests.sh`), no `VNC_PASSWORD` in
`podman inspect` or any process, no `sudo`, the apt cache mounts, noVNC answers on
IPv4 and IPv6, Chrome (on Arch: Chromium) renders a page, a screenshot, the screen can't be locked (`tests/lock.sh`: it sends
every lock request it knows, then checks that typing still reaches a window),
ending the session stops the container and `podman start` brings it back. Build
logs, check output and screenshots go to `$d_test_dir` (default `/tmp/d_test`).
```bash
d_test 20 gnome                    # Ubuntu's gnome on throwaway instance 20
d_distro=debian d_test 20          # every Debian stage
d_distro=archlinux d_test 20       # every Arch Linux stage
```

**Run a program in an instance:** `d_exec COMMAND...` is `podman exec` in the
selected instance without the ambient capabilities `--cap-add` would give it (GTK
programs fail to load icons with them); `d_exec -s` adds the desktop session's
D-Bus environment, and `-d` detaches: `d_exec -s -d gnome-terminal`.

**Automate Chrome in an instance:** `d_chrome [URL...]` starts Chrome on the
selected instance's desktop with its DevTools (remote debugging) port open, inside
the instance only, and `d_chrome_mcp` prints the command that lets Claude Code drive
that browser; `d_devtools` is Chrome DevTools from the shell (`d_devtools list_pages`). `d_distro=chrome d_target=canary` is an image for this: Ubuntu's
`chrome` stage plus Chrome Canary, Puppeteer, Playwright (Node and Python, with
`uv`), their MCP servers and Lighthouse (instances `ccNc`, VNC 7000+N, noVNC 6180+N).
See [chrome/README.md](chrome/README.md) for all of it and the other options.

**OpenCode:** `d_distro=opencode d_target=lxqt d_build`, then `d_select N;
d_distro=opencode d_run` gives Ubuntu's LXQt desktop with OpenCode Desktop in the menu
(Development) and `opencode` (the terminal UI) on the PATH (instances `ocNu`, VNC
7150+N, noVNC 6330+N). See [opencode/README.md](opencode/README.md).

**Remove an instance:** `d_rm [N]` removes the container **and deletes its home
directory** (it asks first; `d_rm -f` doesn't). Default: the selected instance.

**Rebuild after editing the Containerfile:** `d_build`, then `d_select N` and
`d_run` for each instance. Home dirs are untouched.

**Pick up package/Chrome updates:** `d_build` reuses cached layers, so it won't
re-run `apt-get upgrade` or re-download Chrome unless the Containerfile changed.
`d_build_fresh` pulls a newer base image if there is one and rebuilds every layer
(`--pull=newer --no-cache`); then `d_run` each instance. Both pass extra
arguments through to `podman build`, and end with a summary: the time taken and,
per apt step that ran, how much apt downloaded of what it needed (`0 B/105 MB`:
all of it came from the shared cache).
