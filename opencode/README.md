# OpenCode agent desktop (`d_target=lxqt-opencode`)

[OpenCode](https://opencode.ai/product), an open-source AI coding agent, as a desktop
app and a terminal UI, on LXQt (with Google Chrome, TigerVNC/noVNC, nested podman and
the CLI installers). Stages `ubuntu` (the `.deb`) and `fedora` (the `.rpm`) of the
[`Containerfile`](Containerfile) here, built on `vnc-desktop-<distro>:lxqt` and tagged
`vnc-desktop-<distro>:lxqt-opencode`. It builds on amd64 and arm64: the desktop
package's URL follows the image's architecture, and `install_opencode` installs a
native arm64 CLI on arm64.

```bash
source ./env.rc
d_target=lxqt-opencode d_build              # builds vnc-desktop-ubuntu:lxqt first
d_select 1; d_target=lxqt-opencode d_run    # vnc-desktop-ubuntu-opencode-1
d_target=lxqt-opencode d_vnc                # VNC 7151 (needs vncviewer)
d_target=lxqt-opencode d_novnc              # or noVNC on 6331, in a browser
d_distro=fedora d_target=lxqt-opencode d_run    # Fedora's: vnc-desktop-fedora-opencode-1, same ports
```

Keep `d_target=lxqt-opencode` on each line (or set it in your shell or `.env`): the
instance's name, home and ports follow it.

| Distro | Container name and home under `$d_dir` | VNC    | noVNC  |
|--------|----------------------------------------|--------|--------|
| ubuntu | `vnc-desktop-ubuntu-opencode-N`        | 7150+N | 6330+N |
| fedora | `vnc-desktop-fedora-opencode-N`        | 7150+N | 6330+N |

Nested (from inside an instance) it is `<this instance>_ocNu`, so it can't clash with an
Ubuntu child `<this instance>_Nu`.

## What's in it

- **OpenCode Desktop**: in the menu under Development, or run `ai.opencode`.
  It is an Electron app, installed from opencode.ai's "latest" `.deb`
  (`/opt/OpenCode`). GitHub's "latest" release isn't used because it can be an older
  major version. `/usr/local/bin/ai.opencode` is a wrapper that adds:
  - `--no-sandbox`: Chromium's sandbox needs user namespaces or a setuid helper, and
    neither works in a rootless container (the same as Chrome's wrapper).
  - `--password-store=basic`: secrets such as provider logins are stored in a file
    under `~/.config`, not a keyring. LXQt has no keyring daemon, and the user has no
    password to unlock one.
- **`opencode`** (the terminal UI and CLI): a link to the CLI the desktop app bundles
  (`/opt/OpenCode/resources/opencode-cli`), so both are the same version. On its first
  start the app copies that CLI into the home
  (`~/.config/ai.opencode.desktop/cli/<version>/`, about 240 MB) and runs it from there
  as its server (`opencode-cli serve`). It does this every time, and nothing seems to
  turn it off.
- **`install_opencode`**: run it as yourself, like `install_claude`. It installs
  opencode's own build in `~/.opencode/bin` (on the home volume, updates itself) and
  puts that directory first on your PATH in `~/.bashrc`. From the next shell on,
  `opencode` is that copy. Arguments go to opencode's installer, e.g.
  `install_opencode --version 2.3.2`.
- From the base: `fd-find` (`fdfind`), `fzf`, `ripgrep`, `git`, `gh`, `jq`,
  `nodejs`/`npm`, `python3`; from the `lxqt` stage: `featherpad`, a GUI text editor, to
  look at and edit what the agent wrote.

## Updates

The image's copy changes only when you rebuild: `d_target=lxqt-opencode d_build_fresh`,
or `d_build --no-cache`. The desktop app's own updater can't install a package without
root, so its update offers fail. `install_opencode` gives you a terminal UI that keeps
itself up to date between rebuilds.

## Settings and data

They are all in the home, so they outlive the container:
- config: `~/.config/opencode/opencode.json`
- the app's data and sessions: `~/.local/share/opencode`
- the desktop app's settings, and its copy of the CLI: `~/.config/ai.opencode.desktop`

A new home can use OpenCode's free models. Connect another provider with `/connect`
in the terminal UI, or from the desktop app.
