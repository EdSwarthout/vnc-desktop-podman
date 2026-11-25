# vnc-desktop-podman — Desktops over VNC in rootless podman, with Chrome, and nested podman

A rootless-podman container that runs a Linux desktop over VNC/noVNC, with Google Chrome
(Chromium on Arch), nested rootless podman, and installers for Claude Code and other
coding-agent CLIs. Distros and their desktops:

| Distro | Desktops |
|--------|----------|
| Ubuntu 26.04 | XFCE, LXQt, GNOME Flashback, KDE Plasma, MATE, Cinnamon |
| Debian 13 (trixie) | GNOME Shell |
| Fedora 45 | XFCE, LXQt |
| Arch Linux | Openbox (with Chromium) |

On top of a desktop there are [agent desktops](#agent-desktops):
[OpenCode](container/opencode/README.md), [Google Antigravity](container/antigravity/README.md)
and the [Claude desktop app](container/claude/README.md), and there is
an image for [Chrome automation](chrome/README.md). Smaller stages (headless, or VNC
with just an xterm, with or without the browser) come from each distro's own
`Containerfile`. Each instance keeps its home directory on the host, so settings,
browser profile and tools installed there survive rebuilds.

Why use it: [A full Linux desktop for your AI agent, in a rootless container](docs/Advantages-article.md).

| File            | Purpose                                                       |
|-----------------|---------------------------------------------------------------|
| `container/`    | What the images are built from (you normally don't touch it): |
| `container/ubuntu/`, `debian/`, `fedora/`, `archlinux/` | `Containerfile` with the distro's stages `base` → `vnc` → `browser` (see [Images](#images)) |
| `container/xfce/`, `lxqt/`, `gnome/`, `kde/`, `mate/`, `cinnamon/`, `openbox/` | Desktops: a `Containerfile` with one stage per distro that has the desktop, built on that distro's `browser` |
| `container/opencode/`, `antigravity/`, `claude/` | [Agent desktops](#agent-desktops): a `Containerfile` with one stage per distro, built on a desktop, and a README |
| `container/chrome/` | `devtools`: a `Containerfile`, Ubuntu's `browser` + Chrome Canary and browser tools |
| `container/cli-installers/` | `install_claude`, `install_agy`, `install_opencode`, `install_grok`, `install_t3code`, in every `browser` stage (see [CLI installers](#cli-installers)) |
| `container/start.sh` | Container entrypoint (all images): first-boot setup, starts the VNC session if the stage has one |
| `container/vncserver-wrapper` | `/usr/local/bin/vncserver` in every `vnc` stage: runs the VNC X server and the session in the foreground |
| `container/nested-subids` | Fits nested podman's sub-IDs to the container at boot (all images) |
| `user_files/<distro>/` | Your files for new homes (not in git; see [below](#run-an-instance)) |
| `chrome/`       | Chrome automation: `env.rc` (`d_chrome`, `d_chrome_mcp`, `d_devtools`, sourced by the top-level `env.rc`), an example script and a [README](chrome/README.md) of the options |
| `tests/`        | `tests.sh` (nested podman checks), `screenshot.sh` (desktop screenshot), `lock.sh` (the screen can't be locked) |
| `docs/`         | [Screenshots](docs/README.md) of each desktop; [article](docs/Advantages-article.md) on the advantages |
| `env.rc`        | Shell helpers (`d_build`, `d_select`, `d_run`, `d_vnc`, `d_novnc`, `d_exec`, `d_all`, `d_screenshots`, `d_test`, `d_rm`, …)    |
| `.containerignore` | Keeps `d_build`'s context (the repo root) to the files the Containerfiles copy |
| `.env`          | Your VNC password and local settings (not in git)             |

## Requirements

- Linux host, amd64 or arm64 (Arch Linux is amd64 only, and `env.rc` leaves it out on
  arm64), `podman` (rootless).
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
   - `$d_dir/<instance name>` — each instance's home dir, named like the instance
     (Ubuntu's `lxqt`, instance 1 → `$d_dir/vnc-desktop-ubuntu-lxqt-2604-6901`; see
     [Run an instance](#run-an-instance)). Set `d_homes0[debian]=/some/dir` etc. in
     `.env` to keep a distro's homes elsewhere.
   - `$d_dir/apt-cache-<distro>/archives` — downloaded packages, one cache per
     distro, meant to be shared between machines over NFS so packages are
     downloaded once. That's why they're mounted directories rather than a podman
     build cache, which stays local to one machine. They're all called "apt
     cache", though Fedora's holds dnf's rpms (and its repository metadata) and
     Arch's holds pacman's packages. `d_build` mounts the distro's cache on
     `/var/cache/apt-<distro>` (where the image's package manager keeps its
     downloads); `d_run` mounts every one that exists, so a build inside an
     instance uses the right one for any distro (a missing one is skipped with a
     note). Create them:
     `mkdir -p "$d_dir"/apt-cache-{ubuntu,debian,fedora,archlinux}/archives`. On the
     NFS server, export these `archives` directories, e.g.:
     ```
     /mnt/hwd23data/sw/docker/apt-cache-ubuntu/archives hwd4(rw,sync,all_squash,anonuid=1001,anongid=1001)
     /mnt/hwd23data/sw/docker/apt-cache-debian/archives hwd4(rw,sync,all_squash,anonuid=1001,anongid=1001)
     ```
     On a client, mount them at the same paths under that client's `$d_dir`,
     or set `d_aptcaches[ubuntu]=…` etc. in `.env`. Desktops, agent desktops and
     `devtools` use their distro's cache.

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
   d_build    # builds vnc-desktop-ubuntu:browser-2604, then vnc-desktop-ubuntu:lxqt-2604
   ```
   `d_distro` picks the distro (default `ubuntu`) and `d_target` what to build
   (default `lxqt`); see below. To build or run another one without editing
   `env.rc`: `d_target=lxqt d_build`, `d_distro=fedora d_target=lxqt d_run`.

## Images

There are three layers, each built on the one before:

1. **The distro's stages**, in `container/<distro>/Containerfile`: `base` → `vnc` → `browser`.
2. **A desktop**, in `container/<desktop>/Containerfile`, built on the distro's `browser`.
3. **An agent desktop** `<desktop>-<agent>`, in `container/<agent>/Containerfile`, built on
   that desktop: `lxqt-opencode`, `lxqt-antigravity`, `gnome-opencode`,
   `gnome-antigravity`, `gnome-claude`.

`d_target` names any of them; `d_build` builds what it's built on first. A desktop's
or agent's `Containerfile` has one stage per distro that has it, named after the
distro (`FROM … AS fedora`), so a pair that isn't there is refused. Images are
tagged `vnc-desktop-<distro>:<target>-<version>` (`vnc-desktop-ubuntu:browser-2604`,
`vnc-desktop-fedora:lxqt-45`, `vnc-desktop-ubuntu:lxqt-opencode-2604`,
`vnc-desktop-debian:gnome-13`; Arch Linux is rolling and has no version:
`vnc-desktop-archlinux:openbox`), so building one doesn't replace another, and every
one is runnable with `d_run`. The versions are `d_versions` in `env.rc`.

| Target | Adds | Session | Distros |
|--------|------|---------|---------|
| `base`    | network/debug and development tools (compilers, Python, Node, `gh`, `fd`, `fzf`, …), editors, nested rootless podman | none: headless, use `podman exec -it <instance> bash` | all |
| `vnc`     | TigerVNC server/viewer, noVNC | `xterm` | all |
| `browser` | Google Chrome (`--no-sandbox` wrapper; Arch: Chromium), fonts (incl. CJK, emoji), the [CLI installers](#cli-installers) | `xterm` | all |
| `xfce`    | XFCE, `xfce4-screenshooter` | XFCE | ubuntu, fedora |
| `lxqt`    | LXQt with openbox, `screengrab`, `featherpad` | LXQt | ubuntu, fedora |
| `gnome`   | Ubuntu: GNOME Flashback (gnome-panel, metacity, nautilus); Debian: GNOME Shell; `gnome-terminal`, `gnome-screenshot` | GNOME | ubuntu, debian |
| `kde`     | KDE Plasma 6 (X11 session, `kwin-x11`), Dolphin, Konsole, System Settings, `spectacle` | Plasma | ubuntu |
| `mate`    | MATE (mate-panel, marco, caja), `mate-terminal`, `scrot` | MATE | ubuntu |
| `cinnamon` | Cinnamon (software-rendering session), Nemo, `gnome-terminal`, `scrot` | Cinnamon | ubuntu |
| `openbox` | Openbox, a bare window manager, `scrot` | Openbox | archlinux |
| `lxqt-opencode` | [OpenCode](container/opencode/README.md) Desktop and the `opencode` terminal UI | LXQt | ubuntu, fedora |
| `lxqt-antigravity` | [Google Antigravity](container/antigravity/README.md) App and Python SDK | LXQt | ubuntu, fedora |
| `gnome-opencode` | the same as `lxqt-opencode` | GNOME Flashback | ubuntu |
| `gnome-antigravity` | the same as `lxqt-antigravity` | GNOME Flashback | ubuntu |
| `gnome-claude` | the [Claude desktop app](container/claude/README.md) (`claude-desktop`, beta) | GNOME Flashback | ubuntu |
| `devtools` | [Chrome automation](chrome/README.md): Chrome Canary, MCP servers, Puppeteer, Playwright, Lighthouse | Openbox + `xterm` | ubuntu |

[`docs/`](docs/README.md) has a screenshot of each desktop as it first comes up. A
home dir works with any image: the session comes from the image
(`/usr/local/bin/vnc-session`), not the home. No desktop can lock its screen: the
user has no password to unlock it with.

### Desktops

Ubuntu's `gnome` is GNOME Flashback, GNOME's classic X11 desktop, not GNOME Shell:
the GNOME Shell in Ubuntu 26.04 is Wayland-only and needs systemd-logind, so it
can't run as a session on the VNC X server. There is no `gnome-session` either, so
the user menu's **Log Out** does nothing: to end the session (and stop the
container) use **Applications → System Tools → Log Out (stop the container)**, or
`podman stop`.

Debian's `gnome` is **GNOME Shell**: GNOME 48 still has an X11 session. It starts
without systemd, given a stand-in system D-Bus (with no services on it, so GNOME
logs warnings about logind, polkit, UPower etc.). **Power Off → Log Out…** in the
top-right menu ends the session and stops the container (shown although there's
only one user). Screen locking is impossible (no screen shield without GDM). The
dash has Chrome, Files and Terminal.

`kde` runs Plasma's X11 session (`startplasma-x11`), with locking switched off,
both the idle timer and by hand. It is the largest image, about 0.8 GB more than
`browser`. `cinnamon` runs Cinnamon's software-rendering session (`cinnamon2d`), as
there is no GPU behind the VNC display; its screensaver is not run at all.

Fedora's `xfce` and `lxqt` install the desktops' parts by name, not Fedora's
desktop groups (which bring a display manager, NetworkManager, abrt and more), and
no screen locker.

`openbox` (Arch) starts with one xterm on an empty background. Right-click the
background for the menu: **Terminal**, **Chromium**, the window list, and **Exit**,
which ends the session and stops the container. There is no panel. A
`~/.config/openbox/menu.xml` of your own replaces the image's menu; a
`~/.config/openbox/autostart` runs in addition to the image's.


### Agent desktops

An agent desktop is a desktop plus an AI agent's desktop app, built on that desktop's
image (target `<desktop>-<agent>`). Each has its own instances and ports, so it can
run beside the distro's plain desktops. Every image also has the
[CLI installers](#cli-installers) for the agents' terminal tools.

| Target | Adds | Desktop | Distros | VNC / noVNC (host) | README |
|--------|------|---------|---------|--------------------|--------|
| `lxqt-opencode`, `gnome-opencode` | OpenCode Desktop and the `opencode` terminal UI | LXQt (ubuntu, fedora), GNOME Flashback (ubuntu) | see Desktop | 7150+N / 6330+N | [container/opencode](container/opencode/README.md) |
| `lxqt-antigravity`, `gnome-antigravity` | Google Antigravity App and its Python SDK (`install_agy` for the `agy` CLI) | LXQt (ubuntu, fedora), GNOME Flashback (ubuntu) | see Desktop | 7200+N / 6380+N | [container/antigravity](container/antigravity/README.md) |
| `gnome-claude` | the Claude desktop app (`claude-desktop`, beta) | GNOME Flashback | ubuntu | 7400+N / 6580+N | [container/claude](container/claude/README.md) |

```bash
d_target=lxqt-opencode d_build                  # builds vnc-desktop-ubuntu:lxqt-2604 first
d_select 1; d_target=lxqt-opencode d_run        # vnc-desktop-ubuntu-lxqt-opencode-2604-7151
d_distro=fedora d_target=lxqt-opencode d_run    # Fedora's
d_target=gnome-opencode d_run                  # on Ubuntu's GNOME Flashback instead
```

The ports belong to the agent, not the desktop: `lxqt-opencode` and `gnome-opencode`
on the same N want the same ports, so run them on different numbers.

They build on amd64 and arm64. `gnome-claude` is Ubuntu only, as the app is still in
beta; it gives a new home a passwordless keyring for the app's secrets (not
encrypted), see its README.

### Distros

Select one with `d_distro`, per command or in `.env`, together with a target that
distro has (the default, `lxqt`, isn't on Debian or Arch):
```bash
d_distro=debian d_0                      # podman pull docker.io/library/debian:trixie
d_distro=debian d_target=gnome d_build   # vnc-desktop-debian:gnome-13
d_select 5
d_distro=debian d_target=gnome d_run     # vnc-desktop-debian-gnome-13-6955, home $d_dir/vnc-desktop-debian-gnome-13-6955
```
Each distro's instances have their own names, homes and ports (see [Run an
instance](#run-an-instance)), so instance 5 of every distro can run side by side.
Each has its own package cache, because their packages can share a file name but
not the contents.

**Fedora** (`registry.fedoraproject.org/fedora:45`): dnf keeps its downloads and
metadata in `/var/cache/apt-fedora`, so `apt-cache-fedora` is shared like the apt
caches. Chrome is Google's rpm (x86_64 and aarch64).

**Arch Linux** (rolling, amd64 only): Google Chrome isn't in Arch's repositories,
so `browser` has Chromium, with `--no-sandbox` from `/etc/chromium-flags.conf`
(Arch's launcher reads it; no wrapper script). For automation, name the browser:
`d_chrome_bin=chromium d_chrome` (profile `~/.config/chromium-automation`); see
[chrome/README.md](chrome/README.md). Its package cache holds pacman's packages
(the image's pacman has `CacheDir = /var/cache/apt-archlinux/`). noVNC and
websockify aren't packaged, so they come from noVNC's release tarball and PyPI
(`NOVNC_VERSION`, `WEBSOCKIFY_VERSION` build args); `pasta` is a hard link instead
of Arch's symlink, as a host with AppArmor profiles for passt and pasta (Ubuntu)
otherwise confines it with the wrong one and nested containers get no network.

Every distro's `vnc` stage uses the same `vncserver` front end
(`vncserver-wrapper`), as the packaged ones differ (Debian/Ubuntu's is a perl script,
Arch's and Fedora's only work with systemd).

An instance created before a distro's cache directory existed doesn't have it
mounted, so `d_build` for that distro inside it fails until the instance is
recreated with `d_run` from the host (or `d_aptcaches[<distro>]=…` points somewhere
else).

### CLI installers

Every `browser` stage has these in `/usr/local/bin`. Run them as yourself (in a
terminal on the desktop, or with `d_exec`): each runs its vendor's installer into
the home, where the tool persists across rebuilds and updates itself.

| Installer | Installs | Then |
|-----------|----------|------|
| `install_claude` | [Claude Code](https://claude.com/claude-code), `~/.local/bin/claude` | `claude` |
| `install_agy` | the [Antigravity](https://antigravity.google) CLI, `~/.local/bin/agy` | `agy` |
| `install_opencode` | [OpenCode](https://opencode.ai)'s own build, `~/.opencode/bin` (first on PATH via `~/.bashrc`) | `opencode` |
| `install_grok` | xAI's [Grok Build](https://x.ai/cli) CLI, `~/.grok/bin` (first on PATH via `~/.bashrc`) | `grok`; `grok update` |
| `install_t3code` | [T3 Code](https://t3.codes), a web GUI for coding agents: a release in `~/.t3/runtime/versions/<v>` (~500 MB) and `~/.local/bin/t3` | `t3`; `t3 update` |

A new home's `~/.bashrc` puts `~/.local/bin` on PATH when it exists, so these work
in the next shell. Notes:
- `install_grok X.Y.Z` installs that version; `GROK_CHANNEL=alpha install_grok` the
  alpha channel. xAI's installer also links the binary as `agent`; `install_grok`
  removes those links (`grok update` adds `~/.grok/bin/agent` again). On first
  launch `grok` opens Chrome to sign in (`grok login --device-auth` without one).
- `T3CODE_VERSION=X.Y.Z` or `T3CODE_CHANNEL=nightly` for `install_t3code`. `t3`
  serves the GUI on `http://127.0.0.1:3773` (inside the instance) and prints a
  pairing URL: it opens no browser here, so open that URL in Chrome in the
  instance. The agents it drives are CLIs on PATH (`install_claude`). `t3 up` and
  `t3 service` need a systemd user session, which the instance doesn't have.

## Run an instance

Instances are numbered 1-49, separately per distro. The number picks the ports; the
name comes from the image tag and the VNC port (below). The agent desktops and
`devtools` have ports of their own, so they can run beside the distro's desktops; the
same agent on two distros shares its ports. Nested instances, run inside an
instance, are named differently; see item 4 of "Inside the container".

An instance is named after its image and tag, and ends in its VNC host port:
`vnc-desktop-<distro>-<target>[-<version>]-<VNC port>`. Its container, hostname and home
(under `$d_dir`) all have that name.

| Distro / target | Instance N, e.g. | VNC port (host) | noVNC port (host) |
|-----------------|------------------|-----------------|-------------------|
| ubuntu          | `vnc-desktop-ubuntu-lxqt-2604-<6900+N>` | 6900+N | 6080+N |
| debian          | `vnc-desktop-debian-gnome-13-<6950+N>`  | 6950+N | 6130+N |
| archlinux       | `vnc-desktop-archlinux-openbox-<7050+N>` | 7050+N | 6230+N |
| fedora          | `vnc-desktop-fedora-lxqt-45-<7350+N>`   | 7350+N | 6530+N |
| `devtools`      | `vnc-desktop-ubuntu-devtools-2604-<7000+N>` | 7000+N | 6180+N |
| `*-opencode`    | `vnc-desktop-ubuntu-lxqt-opencode-2604-<7150+N>` | 7150+N | 6330+N |
| `*-antigravity` | `vnc-desktop-fedora-lxqt-antigravity-45-<7200+N>` | 7200+N | 6380+N |
| `*-claude`      | `vnc-desktop-ubuntu-gnome-claude-2604-<7400+N>` | 7400+N | 6580+N |

So Ubuntu's `lxqt`, instance 1, is `vnc-desktop-ubuntu-lxqt-2604-6901`, VNC 6901,
noVNC 6081. Every target has its own instance and home, but the ports are per distro
(or per `devtools`/agent row): `xfce` and `lxqt` on the same N want the same ports
(their names end alike), so run them on different numbers. `d_run_new` skips numbers
whose VNC port another container or home already ends in.

`d_select N` only picks the number: the name, home and ports follow
`d_distro` and `d_target` at the time of each command, so after `d_select 1`,
`d_distro=debian d_target=gnome d_run` runs `vnc-desktop-debian-gnome-13-6951`, and
`d_target=lxqt-opencode d_vnc` connects to `vnc-desktop-ubuntu-lxqt-opencode-2604-7151`.

```bash
d_select 1     # or d_run_new: the next number with no container and no home dir yet
d_run          # creates the home dir and starts (or replaces) the container
```

The VNC password never goes into the container's environment (where it would
show in `podman inspect` and be inherited by everything on the desktop). While
the home has no `~/.config/tigervnc/passwd`, `d_run` writes `$VNC_PASSWORD` to
`passwd.init` next to it (mode 600) and refuses to start without one (the
headless `base` stage needs no password); on first start `start.sh` turns that
into `passwd` and deletes it. After that the stored password is used. Inside an
instance, a nested instance copies this instance's `passwd` instead when
`$VNC_PASSWORD` isn't set. `start.sh` also writes an `xstartup` that runs the
image's session, unless the home has one (a customised one is kept).

`d_run` uses `--replace`, so running it again restarts the instance from the
current image; the home dir is kept.

**Your own files in new homes:** put them in `user_files/<distro>/` at the top of
the repo (`user_files/ubuntu/`, `user_files/debian/`, …; gitignored; the desktops and
agent desktops use their distro's; before the `container/` move they were in
`<distro>/user_files/`: move them), laid out as in the home, e.g. `.bashrc`,
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
**Log Out** of the desktop (or exit the `xterm` in `vnc`/`browser`; for Ubuntu's `gnome` see [Desktops](#desktops)). `podman start <name>` brings it back; `podman logs <name>` shows
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
   A new home's `~/.bashrc` puts `~/.local/bin` on PATH when it exists, so tools that
   install there work in the next shell. The other agents' CLIs install the same way
   (see [CLI installers](#cli-installers)).

2. **Set your git identity** (once per instance):
   ```bash
   git config --global user.name  "Your Name"
   git config --global user.email "you@example.com"
   ```

3. **Chrome** (`browser` and up) is in the menu and is the default web
   browser (on Ubuntu and Debian: XFCE's and `xdg-open`'s). It's wrapped to run with `--no-sandbox`
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
   d_target=gnome d_build     # build the target you changed (takes minutes)
   d_run_new                  # pick a free instance number; prints its name
   d_target=gnome d_run       # start it with a new home
   d_vnc                      # look at it (or tests/screenshot.sh, item 5)
   ```
   Inside instance `vnc-desktop-ubuntu-lxqt-2604-6903`, nested instance N is named
   `vnc-desktop-ubuntu-lxqt-2604-6903_<its usual name>`
   (`…-6903_vnc-desktop-ubuntu-gnome-2604-6901`, `…-6903_vnc-desktop-debian-gnome-13-6951`)
   and its home is `~/Containers/<that name>`,
   a plain directory you can read and copy files into.
   It shows that name in its VNC title and shell prompt, though `hostname`
   still says `vnc-desktop-ubuntu-lxqt-2604-6903`. It uses the same VNC password as this instance. To check
   that nested podman itself works, run `tests/tests.sh` (ok/FAIL per check).
   Remove a nested instance when you're done:
   ```bash
   d_rm -f 1                  # = podman rm -f + podman unshare rm -rf of its home
   ```
   Nested instances count against this instance's limit on processes and
   threads (`d_pids_limit` in `env.rc`, 16384; `cat /sys/fs/cgroup/pids.max`
   shows it); podman's default, 2048, is too few for several nested desktops
   ("Resource temporarily unavailable"). The limit is set when the instance is
   created, from the host.
   `podman unshare rm -rf` is needed on the host to delete an instance's
   `.local/share/containers`. How the nesting is set up is described in `CLAUDE.md`.

5. **Screenshots** (any desktop stage): `tests/screenshot.sh [FILE.png]` saves a
   full-screen PNG of the desktop and prints its path (the tool depends on the
   desktop; `d_screenshots` installs `scrot` where none is included).

**No root inside.** The image is meant to carry everything needed: `ed` has no
general `sudo` (the one exception is the boot-time `nested-subids`, which
`start.sh` runs). To add a package, put it in `container/<distro>/Containerfile` (`base`
stage list) and `d_build`, then `d_run`. For a one-off as root, from the host:
`podman exec -u root <instance> apt-get update` / `… apt-get install -y PKG` (Fedora:
`dnf install -y PKG`; Arch: `pacman -Syu --needed PKG`; lost when the container is
replaced). Per-user tools need no root: `pip` in a
`python3 -m venv`, `npm install` in a project or with `--prefix ~/.local`,
and containers in the nested podman.

## Day-to-day

In a new shell, `source env.rc` and `d_select N` before using `d_run`/`d_vnc`/`d_novnc`
(they refuse to run with no instance selected).

```bash
podman ps                  # running instances
podman logs vnc-desktop-ubuntu-lxqt-2604-6901          # entrypoint / VNC / websockify output
podman stop vnc-desktop-ubuntu-lxqt-2604-6901          # stop
podman start vnc-desktop-ubuntu-lxqt-2604-6901         # start again (same container)
podman exec -it vnc-desktop-ubuntu-lxqt-2604-6901 bash # shell without the desktop
```

**Change the VNC password:** delete `<home>/.config/tigervnc/passwd` on
the host, update `.env`, `source env.rc`, then `d_run` again — or run
`vncpasswd` inside the container and restart it.

**Try every target at once:** `d_all N` builds each target of `$d_distro` (Ubuntu: `base vnc browser
xfce lxqt gnome kde mate cinnamon devtools lxqt-opencode lxqt-antigravity gnome-opencode
gnome-antigravity gnome-claude`) and runs it
on instance N, N+1, …, opening a `d_vnc` viewer in the background for each one with a desktop (log
in `/tmp/d_all-<name>.log`). `d_all 11 xfce lxqt` limits it to those targets. N is required, because
`d_run` replaces whatever instance has that number.
What runs once each desktop is up is `$d_all_cmd` (default `d_vnc`): set it in
`.env` or per command to any shell command, which runs with that instance
selected (`$d_name`, `$d_home`, `$d_target`), or to empty for nothing:
```bash
d_all_cmd=d_novnc d_all 11 xfce lxqt                  # browser instead
d_all_cmd='podman logs "$d_name"' d_all 11 gnome      # save each boot log
d_all_cmd= d_all 11                                   # just build and run
```

**Retake the screenshots in `docs/`:** `d_screenshots N [TARGET...]` builds each
desktop, runs it on a new home as instance N (which must be unused; it is
removed again afterwards) and saves `docs/<distro>/<target>.png`.

**Test a target:** `d_test N [TARGET...]` builds each target (default: all of
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
d_distro=debian d_test 20          # every Debian target
d_distro=fedora d_test 20 lxqt     # Fedora's LXQt
```

**Run a program in an instance:** `d_exec COMMAND...` is `podman exec` in the
selected instance without the ambient capabilities `--cap-add` would give it (GTK
programs fail to load icons with them); `d_exec -s` adds the desktop session's
D-Bus environment, and `-d` detaches: `d_exec -s -d gnome-terminal`.
`d_run_cmd [COMMAND...]` (default `bash`) runs a command interactively in a
throwaway container (`--rm`, named `<instance>-cmd`) of the selected instance's image
and home, alongside the instance if it is running (no published ports). It skips
`start.sh`: a new home isn't set up and there is no VNC.

**Automate Chrome in an instance:** `d_chrome [URL...]` starts Chrome on the
selected instance's desktop with its DevTools (remote debugging) port open, inside
the instance only, and `d_chrome_mcp` prints the command that lets Claude Code drive
that browser; `d_devtools` is Chrome DevTools from the shell (`d_devtools list_pages`).
`d_target=devtools` is an image for this: Ubuntu's `browser` plus Chrome Canary,
Puppeteer, Playwright (Node and Python, with `uv`), their MCP servers and Lighthouse
(instances `vnc-desktop-ubuntu-devtools-2604-<7000+N>`, VNC 7000+N, noVNC 6180+N). See [chrome/README.md](chrome/README.md)
for all of it and the other options.

**Agent desktops:** `d_target=lxqt-opencode d_build`, then `d_select N;
d_target=lxqt-opencode d_run` gives LXQt with OpenCode Desktop in the menu
(Development) and `opencode` (the terminal UI) on the PATH. The others are
`lxqt-antigravity`, `gnome-opencode`, `gnome-antigravity` and `gnome-claude`; see
[Agent desktops](#agent-desktops).

**Remove an instance:** `d_rm [N]` removes the container **and deletes its home
directory** (it asks first; `d_rm -f` doesn't). Default: the selected instance.

**Rebuild after editing the Containerfile:** `d_build`, then `d_select N` and
`d_run` for each instance. Home dirs are untouched. Changing a distro's `base`
rebuilds everything on it; a desktop's `Containerfile` only that desktop and its
agent desktops.

**Pick up package/Chrome updates:** `d_build` reuses cached layers, so it won't
re-run the package upgrade or re-download Chrome unless the Containerfile changed.
`d_build_fresh` pulls a newer base image if there is one and rebuilds every layer
(`--pull=newer --no-cache`); then `d_run` each instance. Both pass extra
arguments through to `podman build`, and end with a summary: the time taken and,
per package step that ran, how much was downloaded of what it needed (`0 B/105 MB`:
all of it came from the shared cache; apt, dnf and pacman each report it their own way). Each image gets a short
`org.opencontainers.image.description` label (`podman image inspect`), from
`d_descs` in `env.rc`; `d_description="…" d_build` sets your own.
