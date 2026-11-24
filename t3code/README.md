# T3 Code image (`d_distro=t3code`)

[T3 Code](https://t3.codes), a web GUI for coding agents (Claude Code, Codex, …). It runs
on Ubuntu's `lxqt` stage (LXQt, Google Chrome, TigerVNC/noVNC, nested podman,
`install_claude`). One stage, `lxqt`, tagged `u2604t3code:lxqt`. It builds on amd64 and
arm64: `install_t3code` installs a release for the image's architecture.

```bash
source ./env.rc
d_distro=t3code d_target=lxqt d_build              # builds u2604cc:lxqt first
d_select 1; d_distro=t3code d_target=lxqt d_run    # instance tc1u
d_distro=t3code d_vnc                              # VNC 7301 (needs vncviewer)
d_distro=t3code d_novnc                            # or noVNC on 6481, in a browser
```

Keep `d_target=lxqt` on the `d_run` line: a variable set for the `d_build` command
doesn't stay set in your shell, and `xfce` (the default) isn't a T3 Code stage.

| Distro | Container name | Home                   | VNC    | noVNC  |
|--------|----------------|------------------------|--------|--------|
| t3code | `tcNu`         | `$d_dir/u2604t3codeN`  | 7300+N | 6480+N |

Nested (from inside an instance) it is `<this instance>_tcNu`, so it can't clash with an
Ubuntu child `<this instance>_Nu`.

## What's in it

- **`install_t3code`**: run it as yourself, like `install_claude` (in a terminal on
  the desktop or with `d_exec`). It installs the latest stable T3 Code CLI with T3's
  installer (`https://t3.codes/install.sh`): a self-contained release (~500 MB, no Node
  needed) in `~/.t3/runtime/versions/<version>` and the launcher `~/.local/bin/t3`,
  both on the home volume. If `~/.bashrc` doesn't mention `.local/bin` (a new home's
  doesn't), it adds a block that puts `~/.local/bin` on PATH; from the next shell on,
  `t3` works. `T3CODE_VERSION=X.Y.Z install_t3code` installs that version instead,
  `T3CODE_CHANNEL=nightly install_t3code` follows the nightly train.
- **`t3`**: run it in a terminal on the desktop, in a project directory (or
  `t3 <dir>`). It serves the GUI on `http://127.0.0.1:3773` (inside the instance only)
  and prints a **pairing URL** (`http://localhost:3773/pair#token=…`): it opens no
  browser here, so open that URL in Chrome in the instance. `t3 pair` prints a new one
  for a running server. The agents it drives are CLIs it finds on PATH: install Claude
  Code with `install_claude` (Codex isn't installed, so its "Could not start Codex CLI"
  notice is expected). `t3 serve` runs without a browser.
- `t3 up` and `t3 service` (background service, remote access) need a systemd user
  session, which the instance doesn't have: run `t3` in a terminal instead.
- `fd-find` (`fdfind`), `fzf`: find and pick files, for the agent's shell and yours.
  `ripgrep`, `git`, `gh`, `jq`, `nodejs`/`npm` and `python3` come with the base.
- `featherpad`: a GUI text editor, to look at and edit what the agent wrote.

## Updates

`t3 update` downloads a newer release and switches `~/.local/bin/t3` to it, between
rebuilds. Rebuild with `d_distro=t3code d_build_fresh`, or `d_build --no-cache`, to
refresh the LXQt base and `install_t3code` itself.

## Settings and data

They are all in the home, so they outlive the container: `~/.t3` (releases under
`runtime/versions`, the server's database, projects and threads, auth) and the
launcher `~/.local/bin/t3`. `t3 uninstall` removes the launcher and the downloaded
versions and keeps projects and threads.
