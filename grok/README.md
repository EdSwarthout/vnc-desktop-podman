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

- **`install_grok`**: run it as yourself, like `install_claude`. It installs Grok
  Build with xAI's installer (`https://x.ai/cli/install.sh`) into `~/.grok/bin` (on
  the home volume, updates itself) and puts that directory first on your PATH in
  `~/.bashrc`. From the next shell on, `grok` is that copy. Arguments go to the
  installer, e.g. `install_grok 0.1.42`. `GROK_CHANNEL=alpha install_grok` picks
  the alpha channel (default: stable). After that, `grok update` keeps it current.
- **`grok`** (the terminal UI and CLI): run it in a project directory. On first
  launch it opens Google Chrome in the instance to sign in (`grok login --device-auth`
  if there is no browser; `export XAI_API_KEY=…` for CI). `grok -p "…"` is headless.
- `fd-find` (`fdfind`), `fzf`: find and pick files, for the agent's shell and yours.
  `ripgrep`, `git`, `gh`, `jq`, `nodejs`/`npm` and `python3` come with the base.
- `featherpad`: a GUI text editor, to look at and edit what the agent wrote.

## Updates

`install_grok` gives you a CLI that keeps itself up to date between rebuilds
(`grok update`). Rebuild with `d_distro=grok d_build_fresh`, or `d_build --no-cache`,
to refresh the LXQt base and `install_grok` itself.

## Settings and data

They are all in the home, so they outlive the container:
- the binary and downloads: `~/.grok/bin`, `~/.grok/downloads`
- config: `~/.grok/config.toml`
- sign-in: `~/.grok/auth.json`
