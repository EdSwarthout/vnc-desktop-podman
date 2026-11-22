# GNOME Shell KMS mode on vkms, on the DGX Spark (arm64)

Status: **planned, not started** (2026-11-22). Needs the DGX Spark: this session (cc1u on
hwd23) can't reach it.

## Question

Does `../wayland/`'s KMS mode (`kms.sh`: GNOME Shell 50 as a display server on a vkms card,
mock logind, fake `/run` files) also work on the DGX Spark? It ran on hwd23 (amd64,
2026-11-17, cc8u). The Spark is arm64 and has only an NVIDIA GPU
([intel-igpu-render-node.md](intel-igpu-render-node.md), "DGX Spark" section).

## Expected answer

Yes, the same as on hwd23: one Shell per vkms card (DRM master), rendered on the CPU
(llvmpipe), vkms's preferred 1024x768, viewed over RDP. Nothing in it is amd64-specific,
but the GNOME packages haven't run on arm64 here yet.
- **Different from hwd23**: vkms is `card1` there; `card0` and `renderD128` are the NVIDIA
  GB10 (`logs/dgx-spark-dri.log` in the main checkout). `fake-run.sh` used to tag `card0`
  for the seat, which on the Spark would have been the NVIDIA card. It now finds the vkms
  card itself (or takes `fake-run.sh UID cardN`), and tags only that one, which also hides
  the NVIDIA card from mutter.
- `kms.sh` names no device. The mock logind's `TakeDevice` opens whatever major:minor
  mutter asks for and sets DRM master on it.

Headless mode (`headless.sh`, no vkms, no root step) is the simpler way to run GNOME on
the Spark. This plan covers KMS mode only, to compare.

## Prerequisites (on the Spark host)

1. `sudo modprobe vkms` (once per boot), then check that the card is still `card1`:
   `readlink /sys/class/drm/card1` must contain `/vkms/`. Its number depends on load order.
2. The instance where Claude Code runs gets the vkms card and nothing else under
   `/dev/dri`: `--device /dev/dri/card1 --group-add keep-groups` in `d_run_opts` in the
   Spark's `.env`, then recreate the instance (that stops everything in it).
   **Not** `renderD128`: on the Spark that's the NVIDIA node.
3. Check in the instance: `ls -l /dev/dri` shows only `card1`, and it opens from a nested
   container:
   ```bash
   podman run --rm --security-opt label=disable --userns=keep-id \
       --device /dev/dri/card1 --group-add keep-groups localhost/u2604cc:base \
       bash -c 'exec 3<>/dev/dri/card1 && echo OPEN-OK'
   ```

## Steps (in the instance)

1. **Nested GNOME instance**, as on hwd23 (its `vnc-session` writes the passwordless
   keyring that `rdp.sh`'s credentials go into): `source ./env.rc; d_target=gnome
   d_build`, then `d_run_new` and `d_run_opts="$d_run_opts --device /dev/dri/card1
   --group-add keep-groups" d_target=gnome d_run` (nested name e.g. `cc1u_2u`).
   This is the first `u2604cc:gnome` build on arm64 with the Wayland packages.
2. **Packages**, as root in it (`wayland/README.md`'s list):
   `apt-get update && apt-get install -y --no-install-recommends gnome-shell gnome-session
   gnome-remote-desktop pipewire wireplumber python3-dbus python3-gi openssl freerdp3-x11`.
   Write down any package that's missing or different on arm64.
3. **Scripts**: copy `wayland/` to the nested home as `~/shell` (they hard-code
   `/home/ed/shell`), and put an RDP password in `~/shell/rdp-pass`.
4. **Fake `/run` files**, as root: `podman exec -u root <nested> /home/ed/shell/fake-run.sh`.
   It must print `seat0 card: card1 (226:1)`.
5. **Shell**: as the user, with the ambient caps dropped (`podman exec <nested> setpriv
   --inh-caps=-all --ambient-caps=-all …`): `T=3000 ~/shell/kms.sh`. Check:
   - mutter's log names `/dev/dri/card1` (vkms) and not `card0`;
   - `mock-logind.py`'s log shows `TakeDevice 226 1 /dev/dri/card1` with no `SET_MASTER` error;
   - the Shell keeps running (no `gnome-shell rc=` within the timeout).
6. **RDP**: `~/shell/rdp.sh`, then on the nested instance's Xvnc `:1`:
   `xfreerdp3 /v:127.0.0.1 /u:ed /p:… /cert:ignore -clipboard /size:1024x768`, then
   `tests/screenshot.sh`. Expected: the Shell at 1024x768, mouse input working.
7. **Clean up**: `~/shell/stop.sh`, `d_rm -f N`.

## Then

- Results into the DGX Spark section of
  [intel-igpu-render-node.md](intel-igpu-render-node.md) and into `../wayland/README.md`
  (KMS column: arm64 tested, card number).
- Optional comparison: `MOCK=1 MODE= headless.sh` + `rdp-headless.sh` in the same
  instance, which needs no vkms.
- Later, separately: GNOME headless on the NVIDIA render node via the NVIDIA container
  toolkit's CDI (see the DGX Spark section).

## Resuming

On the Spark, after the prerequisites, in the research worktree:
> Continue research/dgx-spark-gnome-vkms.md
