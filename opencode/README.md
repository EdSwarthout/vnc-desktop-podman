# OpenCode image (`d_distro=opencode`)

[OpenCode](https://opencode.ai/product), an open-source AI coding agent, as a desktop
app and a terminal UI. It runs on Ubuntu's `lxqt` stage (LXQt, Google Chrome,
TigerVNC/noVNC, nested podman, `install_claude`). One stage, `lxqt`, tagged
`u2604opencode:lxqt`. It builds on amd64 and arm64: the desktop `.deb` URL follows
the image's `dpkg --print-architecture`, and `install_opencode` installs a native
arm64 CLI on arm64.

```bash
source ./env.rc
d_distro=opencode d_target=lxqt d_build              # builds u2604cc:lxqt first
d_select 1; d_distro=opencode d_target=lxqt d_run    # instance oc1u
d_distro=opencode d_vnc                              # VNC 7151 (needs vncviewer)
d_distro=opencode d_novnc                            # or noVNC on 6331, in a browser
```

Keep `d_target=lxqt` on the `d_run` line: a variable set for the `d_build` command
doesn't stay set in your shell, and `xfce` (the default) isn't an OpenCode stage.

| Distro   | Container name | Home                    | VNC    | noVNC  |
|----------|----------------|-------------------------|--------|--------|
| opencode | `ocNu`         | `$d_dir/u2604opencodeN` | 7150+N | 6330+N |

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
- `fd-find` (`fdfind`), `fzf`: find and pick files, for the agent's shell and yours.
  `ripgrep`, `git`, `gh`, `jq`, `nodejs`/`npm` and `python3` come with the base.
- `featherpad`: a GUI text editor, to look at and edit what the agent wrote.

## Updates

The image's copy changes only when you rebuild: `d_distro=opencode d_build_fresh`, or
`d_build --no-cache`. The desktop app's own updater can't install a `.deb` without
root, so its update offers fail. `install_opencode` gives you a terminal UI that keeps
itself up to date between rebuilds.

## Settings and data

They are all in the home, so they outlive the container:
- config: `~/.config/opencode/opencode.json`
- the app's data and sessions: `~/.local/share/opencode`
- the desktop app's settings, and its copy of the CLI: `~/.config/ai.opencode.desktop`

A new home can use OpenCode's free models. Connect another provider with `/connect`
in the terminal UI, or from the desktop app.
