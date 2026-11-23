# GNOME Shell KMS mode on vkms, on the DGX Spark (arm64)

Status: **done, works** (2026-11-22, cc1u on the DGX Spark, kernel `7.0.0-1025-nvidia`,
aarch64). Results below; the plan follows unchanged except where marked.

## Result

Yes, the same as on hwd23. GNOME Shell 50.1 ran as a display server on vkms `card1` in a
nested `u2604cc:gnome` instance (`cc1u_1u`), seen over RDP at 1024x768, mouse input
working (a click on the app-grid button opened the grid: `../wayland/kms-arm64.png`).
- **Prerequisites**: the instance had only `card1` under `/dev/dri` (`226:1`, vkms
  under `/sys/devices/faux/vkms/`; `card0` is the NVIDIA GB10 and isn't passed in), and a
  nested container opened it (`OPEN-OK`). `u2604cc:base` has no tag of its own in the
  nested store, so the open test used `u2604cc:chrome`.
- **Build**: `u2604cc:gnome` built on arm64 in 9m12s, all `.deb`s from the shared cache.
- **Packages**: all of `wayland/README.md`'s list exists on arm64 with the same versions as
  amd64's (127 new packages; `gnome-shell` 50.1, `gnome-remote-desktop` 50.2, `freerdp3`
  3.32.2). Nothing missing.
- **`fake-run.sh`**: printed `seat0 card: card1 (226:1)` without being told the card.
- **mutter**: `mock-logind: TakeDevice 226 1 /dev/dri/card1`, `Added device
  '/dev/dri/card1' (vkms) using atomic mode setting`, `Created gbm renderer`, `GPU
  /dev/dri/card1 selected as primary`; no `SET_MASTER` error, no other card mentioned.
  The Shell process mapped `libgallium-26.0.8` (llvmpipe; there's no Mesa driver for the
  GB10, and vkms has no GPU). Ran until `stop.sh`, no `gnome-shell rc=`. The other log
  lines are the same warnings as on hwd23 (no RealtimeKit, GDM, polkit, ibus, GeoClue,
  evolution; document portal can't mount FUSE).
- **RDP** (`rdp.sh`): listened on 3389. `grdctl rdp set-tls-cert` printed `BIO_new
  failed for certificate` / "RDP server certificate is invalid" once, but the status
  showed the certificate and its fingerprint, and the connection worked. The daemon's
  `ZINK: vkCreateInstance failed` and `failed to create dri2 screen` are harmless (it
  falls back to the CPU). xfreerdp3 warns that its NSC codec has no NEON version yet.
- **Not checked in KMS mode**: Chrome as a Wayland client (done in headless mode below);
  resolution change.
- `d_run_opts` is a bash array: step 1's `d_run_opts="$d_run_opts …"` passed a broken
  argument. Use `d_select N; d_run_opts+=(--device /dev/dri/card1 --group-add
  keep-groups); d_target=gnome d_run` (step 1 corrected below).

## Headless mode (same day, for comparison)

A new nested `u2604cc:gnome` instance with **no `/dev/dri`** at all (no `--device`), the
same packages, no root step. Both ways from `../wayland/README.md` work as on hwd23:
- **A**: `MOCK=1 T=3000 headless.sh` (virtual monitor 1440x900) + `rdp.sh` (mirrors it):
  mutter logs `Created surfaceless renderer without GPU` and `Added virtual monitor
  Meta-0`; Shell maps `libgallium` (llvmpipe). Over RDP the full Shell at 1440x900.
  `rdp.sh` printed the same "certificate is invalid" line as in KMS mode, and the
  connection worked anyway.
- **B**: `MOCK=1 MODE= T=3000 headless.sh` (no monitor of its own) + `rdp-headless.sh`:
  the client's `/size:1280x800` became the Shell's only monitor
  (`../wayland/headless-arm64.png`). Credentials in the GKeyFile fallback ("No TPM
  device found"), as on hwd23.
- **Chrome** (`google-chrome-stable --ozone-platform=wayland`, arm64 build) showed as a
  Wayland client in both ways; a click on it went through and left the overview. It logs
  `drmGetDevices2() has not found any devices` (no `/dev/dri`) and renders anyway.
- So on the Spark headless needs nothing from the host, and any number of instances can
  run it. KMS mode gives no advantage there (also CPU, fixed 1024x768, one per card).

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
   d_build`, then `d_run_new`, `d_select N`, then `d_run_opts+=(--device /dev/dri/card1
   --group-add keep-groups); d_target=gnome d_run` (`d_run_opts` is an array; nested name
   e.g. `cc1u_1u`).
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

(Done: results in both files below.)

- Results into the DGX Spark section of
  [intel-igpu-render-node.md](intel-igpu-render-node.md) and into `../wayland/README.md`
  (KMS column: arm64 tested, card number).
- Optional comparison: `MOCK=1 MODE= headless.sh` + `rdp-headless.sh`, which needs no
  vkms. Done: "Headless mode" above.
- Later, separately: GNOME headless on the NVIDIA render node via the NVIDIA container
  toolkit's CDI (see the DGX Spark section).
