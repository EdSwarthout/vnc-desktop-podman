# Google Antigravity agent desktop (`d_target=lxqt-antigravity`, `gnome-antigravity`)

[Google Antigravity](https://antigravity.google), Google's agentic coding platform: the
desktop App, its Python SDK, and an installer for its CLI (`agy`), on LXQt (with
Google Chrome, TigerVNC/noVNC, nested podman and the CLI installers). The
[`Containerfile`](Containerfile) here has the same stage for Ubuntu and Fedora (no
package manager involved), built on `vnc-desktop-<distro>:lxqt-<version>` and tagged
`vnc-desktop-<distro>:lxqt-antigravity-<version>`. It builds on amd64 and arm64: Google
publishes the App, the CLI and the SDK's wheels for both, and it runs on an arm64 DGX
Spark as well as on amd64.

![The Antigravity App in an instance on arm64, and in a nested instance inside it](../../docs/antigravity/lxqt-nested.png)

```bash
source ./env.rc
d_target=lxqt-antigravity d_build              # builds vnc-desktop-ubuntu:lxqt-2604 first
d_select 1; d_target=lxqt-antigravity d_run    # vnc-desktop-ubuntu-lxqt-antigravity-2604-7201
d_target=lxqt-antigravity d_vnc                # VNC 7201 (needs vncviewer)
d_target=lxqt-antigravity d_novnc              # or noVNC on 6381, in a browser
d_distro=fedora d_target=lxqt-antigravity d_run    # Fedora's: vnc-desktop-fedora-lxqt-antigravity-45-7201, same ports
```

On Ubuntu it also comes on GNOME Flashback: `d_target=gnome-antigravity` (built on
`vnc-desktop-ubuntu:gnome-2604`, instances `vnc-desktop-ubuntu-gnome-antigravity-2604-<VNC port>`).
It has the same ports as `lxqt-antigravity`, so run the two on different numbers.

Keep `d_target=lxqt-antigravity` (or `gnome-antigravity`) on each line (or set it in your
shell or `.env`): the instance's name, home and ports follow it.

| Distro | Container name and home under `$d_dir` | VNC    | noVNC  |
|--------|----------------------------------------|--------|--------|
| ubuntu | `vnc-desktop-ubuntu-lxqt-antigravity-2604-<VNC port>` | 7200+N | 6380+N |
| fedora | `vnc-desktop-fedora-lxqt-antigravity-45-<VNC port>` | 7200+N | 6380+N |

Nested (from inside an instance) it is `<this instance>_<that name>`.

## What's in it

- **Antigravity App** (the agent "command center"): in the menu under Development, or
  run `antigravity`. It is an Electron app from Google's Linux tarball, unpacked in
  `/opt/Antigravity`. `/usr/local/bin/antigravity` is a wrapper that adds:
  - `--no-sandbox`: Chromium's sandbox needs user namespaces or a setuid helper, and
    neither works in a rootless container (the same as Chrome's wrapper).
  - `--password-store=basic`: secrets such as the Google sign-in are stored in a file
    under `~/.config`, not a keyring. LXQt has no keyring daemon, and the user has no
    password to unlock one.

  Sign-in opens Google Chrome in the instance.
- **`install_agy`**: installs the Antigravity CLI with Google's installer
  (`https://antigravity.google/cli/install.sh`) into `~/.local/bin/agy`, on the home
  volume, where it updates itself, like `install_claude`. Run it once per home, as
  the user. Arguments go to the installer (`--dir PATH`).
- **Python SDK** ([antigravity-sdk-python](https://github.com/google-antigravity/antigravity-sdk-python)):
  `google-antigravity` from PyPI, whose wheels carry the compiled runtime the SDK runs
  (cloning the repository isn't enough). It is in a virtual environment, `/opt/venv`,
  first on the PATH, so `python3` finds it:
  ```bash
  export GEMINI_API_KEY=…     # or Vertex AI: see the SDK's README
  python3 -c 'from google.antigravity import Agent, LocalAgentConfig'
  ```
  Examples are in the repository's `examples/`, and a skill for coding agents in
  `skills/google-antigravity-sdk` (not part of the wheel: copy it to
  `~/.claude/skills` if you want it). The venv and `uv` (`/opt/uv/bin`) belong to
  the user, so `uv pip install -U google-antigravity` or other packages need no root;
  they are lost when the instance is replaced (the venv is in the image, not the home).

## Updating

- **App**: the image has the newest release at build time. Its own updater can't
  write to `/opt`: rebuild with `d_target=lxqt-antigravity d_build_fresh`.
  To pin a version: `d_target=lxqt-antigravity d_build --build-arg
  ANTIGRAVITY_VERSION=2.34.0` (a version from
  `https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/releases`),
  or `--build-arg ANTIGRAVITY_TGZ=<url>` for a given tarball.
- **CLI**: updates itself in `~/.local/bin`.
- **SDK**: `uv pip install -U google-antigravity` for this instance, or rebuild;
  `--build-arg ANTIGRAVITY_SDK_VERSION=…` pins it.

The Antigravity IDE (the standalone VS Code-based editor) is not included.
