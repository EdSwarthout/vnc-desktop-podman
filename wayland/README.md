# GNOME Shell on Wayland (Ubuntu 26.04): experiment notes

Status: **experiment only**, 2026-11-17; GPU render node and headless RDP 2026-11-22.
Nothing here is wired into a Containerfile,
`env.rc` or the tests. The scripts are the ones used in the throwaway instance, with
`/home/ed/shell` and uid 1001 hard-coded.

## Result

GNOME Shell 50.1 (Wayland-only) runs in a nested Ubuntu instance without systemd, two ways.
Both were seen over RDP with Chrome running as a Wayland client and mouse input working.

| | `--headless` (recommended) | KMS on vkms `card0` |
|---|---|---|
| Script | `headless.sh` (`MOCK=1`) | `kms.sh` |
| Host setup | none | `modprobe vkms`, `--device /dev/dri/card0` |
| Root in the instance | none | fake `/run` files (`fake-run.sh`) |
| Instances at once | any number | one (single DRM master: a second `SET_MASTER` gets EACCES) |
| Resolution | `--virtual-monitor WxH` (1440x900 tested) | vkms's preferred 1024x768; switching not tried |
| Screenshot | `headless.png` | `kms.png` |
| GPU | any render node passed in (below) | none (vkms; CPU) |

**With a GPU render node** (2026-11-22, Intel iGPU, instance with only
`--device /dev/dri/renderD128 --group-add keep-groups`): `--headless` uses it with no
change to the scripts. mutter logs `Added device '/dev/dri/renderD128' (i915) using no
mode setting` and `Created gbm renderer`; `COGL_DEBUG=winsys,driver` prints `GL_RENDERER:
Mesa Intel(R) Graphics (RPL-S)`, GL 4.6. Two shells ran at once on the same node. Over RDP
(`rdp-headless.sh`, `headless-gpu.png`) the full Shell showed, and a click went through.
gnome-shell's fd on the node gains i915 render time as the screen changes
(`/proc/<pid>/fdinfo/*`, `drm-engine-render`). gnome-remote-desktop holds no render-node
fd: it copies and encodes on the CPU (it looks for CUDA/NVENC and finds none).

## What it needs

- **Private system bus**: `dbus-daemon` as the user with `system-bus.conf`, address in
  `DBUS_SYSTEM_BUS_ADDRESS` (same idea as Debian's `vnc-system-bus.conf`).
- **Mock logind** (`mock-logind.py`, needs `python3-dbus`, `python3-gi`) on that bus:
  Manager, Session, Seat and User objects.
  - Headless with an empty bus starts but logs "Could not get a proxy for user …
    login1" and "Failed to start state machine"; with the mock it starts cleanly.
  - Headless never calls `TakeDevice`, so that part is only for KMS.
- **KMS only**: mutter wants a logind session ("Failed to find any matching session")
  and a udev `seat` tag on the card. `fake-run.sh` (as root) writes
  `/run/systemd/{users,sessions,seats}` and `/run/udev/{data,tags}` for `card0` only,
  which also hides the host's other cards visible in `/sys`.
- **Headless RDP** (`rdp-headless.sh`, 2026-11-22): `gnome-remote-desktop-daemon
  --headless` gives each client a virtual monitor of its own, so run `headless.sh` with
  `MODE=` (no monitor of the shell's own). Otherwise the client sees a second, empty
  monitor, and the top bar stays on the first. No keyring needed: headless mode keeps the
  credentials in `~/.local/share/gnome-remote-desktop/credentials.ini`, with settings
  under the `org.gnome.desktop.remote-desktop.rdp.headless` schema. `grdctl --headless rdp
  enable` wants systemd, so set the schema's `enable` key with gsettings. Set the
  credentials before the daemon starts: changed under a running daemon, logins fail with
  `SEC_E_MESSAGE_ALTERED`.
- **Remote access is RDP**: Ubuntu's `gnome-remote-desktop` has no VNC backend, so
  TigerVNC/noVNC can't connect. `rdp.sh` starts `pipewire`, `wireplumber` and the daemon.
  - `grdctl rdp enable` fails without systemd and leaves RDP disabled:
    `gsettings set org.gnome.desktop.remote-desktop.rdp enable true` instead.
  - The daemon aborts when its FUSE clipboard mount fails (`fusermount3: mount failed:
    Permission denied`): connect with the clipboard off, e.g.
    `xfreerdp3 /v:127.0.0.1 /u:ed /p:… /cert:ignore -clipboard /size:1440x900`.
  - Credentials went into the home's passwordless default keyring (from the `gnome`
    stage's `vnc-session`).
- **Packages added** to `u2604cc:gnome` for the test (`--no-install-recommends`):
  `gnome-shell gnome-session gnome-remote-desktop pipewire wireplumber python3-dbus
  python3-gi openssl freerdp3-x11` (the last one only as a test client).

## How it was run

In a nested `u2604cc:gnome` instance, each via `podman exec … setpriv --inh-caps=-all
--ambient-caps=-all`:

1. `MOCK=1 T=3000 headless.sh` (or `kms.sh` after `fake-run.sh` as root). With a GPU:
   `--device /dev/dri/renderD128 --group-add keep-groups` on the nested instance.
2. `rdp.sh` (reads the password from `rdp-pass`, makes a self-signed TLS cert), or with
   `MODE= headless.sh`: `rdp-headless.sh`.
3. `xfreerdp3` on the instance's Xvnc `:1`, then `tests/screenshot.sh`.
4. Wayland clients: `. env.sh; google-chrome-stable --ozone-platform=wayland`.
5. `stop.sh` ends it all. Don't `pkill -f PATTERN` from a `podman exec sh -c` line
   that contains the pattern: it kills its own shell.

## Not done / open

- `gnome-session` and gnome-settings-daemon (only bare `gnome-shell --no-x11` ran), Xwayland.
- Screen lock must be impossible, and Log Out must end the container: both untested.
- A screenshot route: `gnome-screenshot` hangs, and `org.gnome.Shell.Screenshot` answers
  "Screenshot is not allowed".
- A browser-reachable client (noVNC can't speak RDP), and which port to publish.
- Whether an empty private bus is usable enough to skip the mock.
- The nested instance's Flashback session ended once during the tests ("The X session
  cleanly exited"); cause unknown.
- vkms note: `card0` is vkms only by load order (simpledrm had minor 0 at boot); the
  `/dev/dri/by-path` link for it is stale. GPU acceleration needs a render node
  (`renderD128`), not vkms (done for `--headless`, above).
- The GPU runs were in a throwaway container from `u2604cc:base` + `gnome-shell
  gnome-remote-desktop pipewire wireplumber python3-dbus python3-gi dbus-x11 openssl` and,
  as a test client, `freerdp3-x11 xvfb scrot xdotool`. They were not run in a nested
  `u2604cc:gnome` instance as above. The host desktop wasn't watched.
