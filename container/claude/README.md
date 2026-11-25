# Claude desktop agent desktop (`d_target=gnome-claude`)

Anthropic's Claude desktop app (`claude-desktop`, still in beta) on Ubuntu's GNOME
Flashback (with Google Chrome, TigerVNC/noVNC, nested podman and the CLI installers).
Stage `ubuntu` of the [`Containerfile`](Containerfile) here, built on
`vnc-desktop-ubuntu:gnome-2604` and tagged `vnc-desktop-ubuntu:gnome-claude-2604`.
Because the app is in beta, it is built on Ubuntu's GNOME only, not on the other
desktops or distros. Anthropic's apt repository has amd64 and arm64 packages.

```bash
source ./env.rc
d_target=gnome-claude d_build              # builds vnc-desktop-ubuntu:gnome-2604 first
d_select 1; d_target=gnome-claude d_run    # vnc-desktop-ubuntu-gnome-claude-2604-7401
d_target=gnome-claude d_vnc                # VNC 7401 (needs vncviewer)
d_target=gnome-claude d_novnc              # or noVNC on 6581, in a browser
```

Keep `d_target=gnome-claude` on each line (or set it in your shell or `.env`): the
instance's name, home and ports follow it.

| Distro | Container name and home under `$d_dir` | VNC    | noVNC  |
|--------|----------------------------------------|--------|--------|
| ubuntu | `vnc-desktop-ubuntu-gnome-claude-2604-<VNC port>` | 7400+N | 6580+N |

Nested (from inside an instance) it is `<this instance>_<that name>`.

## What's in it

- **Claude desktop**: from the app's menu entry, or run `claude-desktop`. It comes
  from Anthropic's apt repository: the build downloads the repository's signing key
  (`https://downloads.claude.ai/keys/claude-code.asc`) and writes
  `claude-desktop.list`, both where the package's own postinst puts them, so it
  doesn't add a second entry. It is installed with its recommended packages (the
  desktops' package lists leave those out), plus `gnome-keyring`.
- **A keyring that never asks for a password**: the app keeps its secrets in the
  default GNOME keyring. A new home has none, and gnome-keyring's "choose a password"
  dialog left the app hanging. So `/usr/local/bin/claude-desktop`, a wrapper ahead of
  `/usr/bin` on `PATH`, gives a home without a default keyring a passwordless one
  (`~/.local/share/keyrings/Default_keyring.keyring` and `default`) before it starts
  the app. That keyring unlocks without a prompt. The menu entry runs the bare
  `claude-desktop` command, so it finds the wrapper too; the build fails if an
  `Exec=` line doesn't.
  - Secrets in that keyring are **not encrypted**: only the home's file permissions
    protect them. There's no user password to encrypt them with.
  - A home that already has a default keyring keeps it.
- Everything from GNOME Flashback (`gnome`): see "Desktops" in the main
  [README](../../README.md#desktops). To end the session (and stop the container), use
  **Applications → System Tools → Log Out (stop the container)**.

## Updating

The app comes from the apt repository at build time, and the user has no root in the
instance, so rebuild to update: `d_target=gnome-claude d_build`, then `d_run`. The
home is kept.

## Starting it from a script

A plain `podman exec` has no session bus, and the app needs one (for the keyring).
Start it the way the desktop would, with the session's D-Bus environment:

```bash
d_target=gnome-claude d_exec -s -d claude-desktop
```
