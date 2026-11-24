# Grok image (`d_distro=grok`)

[Grok Build](https://x.ai/cli), xAI's coding agent for the terminal. It runs on Ubuntu's
`lxqt` stage (LXQt, Google Chrome, TigerVNC/noVNC, nested podman, `install_claude`). One
stage, `lxqt`, tagged `u2604grok:lxqt`. It builds on amd64 and arm64: `install_grok`
installs a native binary for the image's architecture.

```bash
source ./env.rc
d_distro=grok d_target=lxqt d_build              # builds u2604cc:lxqt first
d_select 1; d_distro=grok d_target=lxqt d_run    # instance gk1u
d_distro=grok d_vnc                              # VNC 7251 (needs vncviewer)
d_distro=grok d_novnc                            # or noVNC on 6431, in a browser
```

Keep `d_target=lxqt` on the `d_run` line: a variable set for the `d_build` command
doesn't stay set in your shell, and `xfce` (the default) isn't a Grok stage.

| Distro | Container name | Home                 | VNC    | noVNC  |
|--------|----------------|----------------------|--------|--------|
| grok   | `gkNu`         | `$d_dir/u2604grokN`  | 7250+N | 6430+N |

Nested (from inside an instance) it is `<this instance>_gkNu`, so it can't clash with an
Ubuntu child `<this instance>_Nu`.

## What's in it

- **`install_grok`**: run it as yourself, like `install_claude` (in a terminal on the
  desktop or with `d_exec`). It installs the latest version of Grok Build with xAI's
  installer (`https://x.ai/cli/install.sh`) into `~/.grok/bin` (on the home volume,
  updates itself) and puts that directory first on your PATH in `~/.bashrc`. From the
  next shell on, `grok` is that copy. A version argument installs that version instead
  (`install_grok X.Y.Z`); `GROK_CHANNEL=alpha install_grok` picks the alpha channel
  (default: stable). After that, `grok update` keeps it current. xAI's installer also
  links the binary as `agent` (in `~/.grok/bin`, and in `~/.local/bin` if `~/.grok/bin`
  isn't on PATH yet); `install_grok` removes those links, as `agent` is too generic a
  name to put first on PATH. Run `grok`. `grok update` links `~/.grok/bin/agent`
  again (`rm ~/.grok/bin/agent`, or run `install_grok` instead of `grok update`).
- **`grok`** (the terminal UI and CLI): run it in a project directory. On first
  launch it opens Google Chrome in the instance to sign in (`grok login --device-auth`
  if there is no browser; `export XAI_API_KEY=…` for CI). `grok -p "…"` is headless.
- From the base: `fd-find` (`fdfind`), `fzf`, `ripgrep`, `git`, `gh`, `jq`,
  `nodejs`/`npm`, `python3`; from the `lxqt` stage: `featherpad`, a GUI text editor, to
  look at and edit what the agent wrote.

## Updates

`install_grok` gives you a CLI that keeps itself up to date between rebuilds
(`grok update`). Rebuild with `d_distro=grok d_build_fresh`, or `d_build --no-cache`,
to refresh the LXQt base and `install_grok` itself.

## Settings and data

They are all in the home, so they outlive the container:
- the binary and downloads: `~/.grok/bin`, `~/.grok/downloads`
- config: `~/.grok/config.toml`
- sign-in: `~/.grok/auth.json`
