---
name: add-agent-desktop
description: >-
  Checklist and procedure for adding an AI agent desktop (<desktop>-<agent>, e.g.
  lxqt-opencode, gnome-antigravity, gnome-claude) or extending an existing agent desktop
  to another distro or desktop in vnc-desktop-podman. Use when packaging Electron/GUI
  agent apps, SDK venvs, keyrings, or wiring agent desktop ports and docs.
---

# Adding an Agent Desktop

Agent desktops are Layer 3 images built on top of a distro's desktop stage
(`BASE=localhost/vnc-desktop-<distro>:<desktop>[-<version>]`), named `<desktop>-<agent>`.

## Procedure

1. **Create or extend `container/<agent>/Containerfile`:**
   - Default `ARG BASE=localhost/vnc-desktop-<distro>:<desktop>[-<version>]` and a header
     comment listing stages.
   - Declare `ARG USERID`, `ARG USER_UID`, `ARG USER_GID` in each stage to avoid unconsumed
     build-arg warnings.
   - If installation is distro-independent (no package manager, e.g. tarball + PyPI), use a
     single shared stage `FROM ${BASE} AS app` and alias distros with `FROM app AS ubuntu`,
     `FROM app AS fedora` (see `container/antigravity/Containerfile`).
   - If `.deb` vs `.rpm` differ but post-install setup is identical, factor post-install
     into a shared script (see `container/opencode/setup-opencode.sh`) and add a `!` entry
     to `.containerignore`.
   - Keep builds **architecture-neutral** (amd64 + arm64): use `dpkg --print-architecture`
     for `.deb` URLs and `uname -m` for `.rpm`/tarball URLs.
   - For tarball installs without a package manager, verify runtime libraries at build time
     with `ldd` (fail the build on any `not found`).

2. **Containerize the GUI app (Electron / keyring / sandbox):**
   - Electron/Chromium apps need `--no-sandbox` inside rootless containers. Install a
     wrapper in `/usr/local/bin/<app>` (ahead of `/usr/bin` on `PATH`) and point all
     `/usr/share/applications/*.desktop` `Exec=` lines at it, paired with `grep -q` build
     assertions so upstream path changes fail the build.
   - Secrets/keyring (the container user has no password):
     - Prefer `--password-store=basic` when supported (stores secrets in `~/.config`, works
       on desktops without a keyring daemon like LXQt).
     - If the app requires `gnome-keyring` (like `claude-desktop`), seed a passwordless
       plaintext keyring on first launch in the wrapper when
       `~/.local/share/keyrings/default` is absent, and document that secrets are
       unencrypted on disk.
   - If the app includes a Python SDK or tool venv, put `uv` in `/opt/uv` and the venv in
     `/opt/venv` (outside the home volume so the bind mount doesn't hide it), owned by
     `"${USERID}:$(id -gn "${USERID}")"`, with `/opt/venv/bin:/opt/uv/bin` first on `PATH`
     and `VIRTUAL_ENV=/opt/venv`.
   - End the stage with `USER ${USERID}`.

3. **Wire into `env.rc`:**
   - Add `<agent>` to `d_agents`.
   - Allocate a dedicated VNC / noVNC port base pair in `d_vnc_ports0` and `d_novnc_ports0`
     (unused 50-port block; avoid 7100/6280 used by `omarchy`). Ports belong to the agent
     layer (shared across desktops and distros for that agent).
   - Add `<desktop>-<agent>` entries to `d_targets_<distro>` and update the `d_target`
     comment.
   - Add `<agent>` description to `d_descs` (`_d_desc` combines `<agent>; <desktop>`).

4. **Update documentation:**
   - Create/update `container/<agent>/README.md` covering build/run commands, ports table,
     what's included, sandbox/keyring tradeoffs, updating (`d_build_fresh` / `--no-cache`),
     and starting from scripts (`d_exec -s -d`).
   - Update main `README.md`: intro, file table, Images table, Agent desktops table,
     `d_all` list, and Day-to-day section.
   - Update `AGENTS.md`: intro and `container/` summary.

## Validation
- `shellcheck` passes on all scripts and `bash tests/test_env.sh` passes.
- `[d_distro=<distro>] d_test N <desktop>-<agent>` passes (`0 failed`), with zero
  unconsumed build-arg warnings.
- Verify the app actually launches on the desktop via `d_exec -s -d <app>` (with
  `d_test_keep=1`), capture a screenshot with `tests/screenshot.sh`, and inspect the PNG.
- Verify any bundled CLI or Python SDK imports cleanly inside the running container.
