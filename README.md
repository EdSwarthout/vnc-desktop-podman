# vnc-desktop-podman — Desktops over VNC in rootless podman, with Chrome, and nested podman

A rootless-podman container that runs an XFCE, LXQt, GNOME Flashback, KDE Plasma, MATE or Cinnamon desktop over VNC/noVNC,
with Google Chrome, Claude Code and nested rootless podman. Smaller stages
(headless, or VNC with just an xterm) are built from the same `Containerfile`.
Each instance keeps its home directory on the host, so settings, browser profile
and the Claude install survive rebuilds.

| File            | Purpose                                                       |
|-----------------|---------------------------------------------------------------|
| `Containerfile` | Image stages `base` → `vnc` → `chrome` → `xfce` / `lxqt` / `gnome` / `kde` / `mate` / `cinnamon` (see [Stages](#stages)) |
| `start.sh`      | Container entrypoint: first-boot setup, starts the VNC session if the stage has one |
| `nested-subids` | Fits nested podman's sub-IDs to the container at boot |
| `tests/`        | `tests.sh` (nested podman checks), `screenshot.sh` (desktop screenshot) |
| `docs/`         | [Screenshots](docs/README.md) of each stage's desktop          |
| `env.rc`        | Shell helpers (`d_build`, `d_select`, `d_run`, `d_vnc`, `d_novnc`, …)    |
| `.env`          | Your VNC password and local settings (not in git)             |

## Requirements

- Linux host, amd64 (the Chrome `.deb` is amd64-only), `podman` (rootless).
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
   - `d_home0=$d_dir/u2604cc` — prefix for each instance's home dir
     (instance 1 → `$d_dir/u2604cc1`).
   - `d_aptcache=$d_dir/apt-cache/archives` — downloaded `.deb`s, mounted on
     `/var/cache/apt/archives` in builds and containers, and meant to be
     shared between machines over NFS so packages are downloaded once. That's
     why it's a mounted directory rather than a podman build cache, which
     stays local to one machine. Create it: `mkdir -p "$d_aptcache"` (after
     step 3). On the NFS server, export this `archives` directory, e.g.:
     ```
     /mnt/hwd23data/sw/docker/apt-cache/archives hwd4(rw,sync,all_squash,anonuid=1001,anongid=1001)
     ```
     On a client, mount it at that client's `$d_aptcache`.

2. **Create `.env`** next to `env.rc` with the VNC password (VNC only uses
   the first 8 characters) and your `d_dir`. `env.rc` sources it, so it can
   override any of the defaults at the top of `env.rc` (`d_dir`, `d_user`,
   `d_target`, `d_aptcache`, `d_home0`):
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
   d_build    # podman build -t u2604cc:$d_target --target $d_target …
   ```
   `d_target` in `env.rc` picks the stage (default `xfce`); see below. To build
   or run another one without editing `env.rc`: `d_target=lxqt d_build`,
   `d_target=lxqt d_run`.

## Stages

Each stage builds on the one before; `xfce`, `lxqt`, `gnome`, `kde`, `mate` and `cinnamon` each build on `chrome`.
Every stage is runnable with `d_run`, and the image is tagged `u2604cc:<stage>`,
so building one doesn't replace another.

| Stage    | Adds                                                        | Session        |
|----------|-------------------------------------------------------------|----------------|
| `base`   | Ubuntu, network/debug and development tools (compilers, Python, Node, `gh`, …), editors, nested rootless podman, `install_claude` | none: headless, use `podman exec -it ccN bash` |
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

## Run an instance

Instances are numbered. On the host, instance N is named `ccN`, uses home
`${d_home0}N`, and publishes (nested instances, run inside an instance, are
named differently; see item 4 of "Inside the container"):

| Instance | Container name | VNC port (host) | noVNC port (host) |
|----------|----------------|-----------------|-------------------|
| 1        | `cc1`          | 6901            | 6081              |
| 2        | `cc2`          | 6902            | 6082              |
| N        | `ccN`          | 6900+N          | 6080+N            |

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

Instances use the host's timezone (`--tz=local`); a nested one gets its parent
instance's.

The container stops if the VNC server or websockify exits — including when you
**Log Out** of the desktop (or exit the `xterm` in `vnc`/`chrome`; for `gnome` see [Stages](#stages)). `podman start ccN` brings it back; `podman logs ccN` shows
which one exited.

## Connect to the desktop

- **Browser (noVNC):** `d_novnc` opens the selected instance's page in your
  default browser (`xdg-open`); from another machine it's
  `http://<host>:6081/vnc.html` for instance 1 (6080+N in general). Then
  enter the VNC password.
- **VNC client:** `d_vnc` runs `vncviewer` against the selected instance using
  its stored password file. From another machine, point a VNC client at
  `<host>:6901` (6900+N).

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
   Inside instance `cc3`, nested instance N is named `cc3_N` and its home is
   `~/Containers/cc3_N`, a plain directory you can read and copy files into.
   It shows that name in its VNC title and shell prompt, though `hostname`
   still says `cc3`. It uses the same VNC password as this instance. To check
   that nested podman itself works, run `tests/tests.sh` (ok/FAIL per check).
   Remove a nested instance when you're done:
   ```bash
   podman rm -f -t 2 cc3_1
   podman unshare rm -rf ~/Containers/cc3_1    # plain rm can't delete all of it
   ```
   The same `podman unshare rm -rf` is needed on the host to delete an
   instance's `.local/share/containers`. If `start.sh` warns at boot about
   older nested storage, run `podman system reset` once as it says. How the
   nesting is set up is described in `CLAUDE.md`.

5. **Screenshots** (`xfce`, `lxqt`, `gnome`, `kde`, `mate`, `cinnamon`): `tests/screenshot.sh [FILE.png]` saves a
   full-screen PNG of the desktop and prints its path.

**No root inside.** The image is meant to carry everything needed: `ed` has no
general `sudo` (the one exception is the boot-time `nested-subids`, which
`start.sh` runs). To add a package, put it in the `Containerfile` (`base`
stage list) and `d_build`, then `d_run`. For a one-off as root, from the host:
`podman exec -u root ccN apt-get update` / `… apt-get install -y PKG` (lost
when the container is replaced). Per-user tools need no root: `pip` in a
`python3 -m venv`, `npm install` in a project or with `--prefix ~/.local`,
and containers in the nested podman.

## Day-to-day

In a new shell, `source env.rc` and `d_select N` before using `d_run`/`d_vnc`/`d_novnc`
(they refuse to run with no instance selected).

```bash
podman ps                  # running instances
podman logs cc1            # entrypoint / VNC / websockify output
podman stop cc1            # stop
podman start cc1           # start again (same container)
podman exec -it cc1 bash   # shell without the desktop
```

**Change the VNC password:** delete `${d_home0}N/.config/tigervnc/passwd` on
the host, update `.env`, `source env.rc`, then `d_run` again — or run
`vncpasswd` inside the container and restart it.

**Try every stage at once:** `d_all N` builds each stage (`base vnc chrome
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
removed again afterwards) and saves `docs/<stage>.png`.

**Rebuild after editing the Containerfile:** `d_build`, then `d_select N` and
`d_run` for each instance. Home dirs are untouched.

**Pick up package/Chrome updates:** `d_build` reuses cached layers, so it won't
re-run `apt-get upgrade` or re-download Chrome unless the Containerfile changed.
`d_build_fresh` pulls a newer base image if there is one and rebuilds every layer
(`--pull=newer --no-cache`); then `d_run` each instance. Both pass extra
arguments through to `podman build`.
