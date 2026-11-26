# Wayland Desktops in Rootless Podman — Plan

Status: **planned** (branched from `main` at `eed45b9`; informed by review of `origin/research` at `3307cbf`).

## 1. Review of `origin/research` Findings

All experiments on `origin/research` (`wayland/`, `container/omarchy/`, `research/*.md`) were reviewed. Key takeaways that shape this plan:

### What is proven
1. **GNOME Shell 50.1 (`--headless`) works without systemd on both amd64 and arm64:**
   - Needs only a private per-user system D-Bus (`system-bus.conf`) + `mock-logind.py` (`python3-dbus`, `python3-gi`). No host kernel modules (`vkms`), no root `/run` fakes, and unlimited concurrent instances.
   - **Zero-GPU (CPU/llvmpipe)** works out of the box on both amd64 (`hwd23`) and arm64 (`DGX Spark`).
   - **Mesa GPU render node** (`--device /dev/dri/renderD128 --group-add keep-groups` on Intel iGPU) is picked up automatically by mutter (`Created gbm renderer`, Mesa GL 4.6) with multiple concurrent shells on one GPU.
   - **Headless RDP (`gnome-remote-desktop-daemon --headless`)** works without a keyring (stores credentials in `~/.local/share/gnome-remote-desktop/credentials.ini`), gives each client its own virtual monitor (start `gnome-shell` with no `--virtual-monitor` so there is no phantom second screen), and accepts Chrome (`--ozone-platform=wayland`) + mouse input.
2. **KMS mode on `vkms` is a dead end for GNOME:**
   - Proven on amd64 (`card0`) and arm64 (`card1`), but adds host `modprobe vkms`, root `/run` files (`fake-run.sh`), fixed 1024×768 resolution, and a 1-instance-per-card DRM master limit — while still rendering on the CPU. **Drop KMS/`vkms` for GNOME.**
3. **wlroots (`labwc` + `wayvnc` + `noVNC`) is the cleanest VNC-native Wayland path:**
   - `labwc` runs in `WLR_BACKENDS=headless` with either CPU or Mesa render-node acceleration (`WLR_RENDER_DRM_DEVICE`), has no file caps that break nested podman (unlike Arch's `sway` with `cap_sys_nice=ep`), and speaks standard VNC/noVNC via `wayvnc -r` + `websockify`.
4. **Omarchy (`container/omarchy/`, Arch + Hyprland 0.56.2) works on amd64 only:**
   - Standalone (`o_*` helpers, 7.5 GB ISO btrfs rootfs). Works on `vkms` (1 instance/card) or on an Intel Mesa render node (`o_render=1`) by nesting Hyprland inside headless `labwc` with two aquamarine 0.15.1 workarounds (fixed upstream in aquamarine 0.16.0).
   - Cannot run on arm64 (x86 ISO, Arch is amd64-only) and is not yet integrated with `start.sh`, `nested-subids`, `vnc-pkg`, or VNC passwords.
5. **Heterogeneous GPU caveat (`hwd23` vs `DGX Spark`):**
   - On `hwd23`, `/dev/dri/renderD128` is the Intel iGPU (Mesa `iris`) and `renderD129` is NVIDIA RTX 4090.
   - On `DGX Spark` (arm64), `/dev/dri/renderD128` is the NVIDIA GB10 (no Mesa driver; would require NVIDIA Container Toolkit CDI, untested rootless/nested).
   - **Rule:** Never hardcode `--device /dev/dri/renderD128` in shared `d_run_opts`. GPU pass-through must be explicit opt-in or vendor-checked (Mesa Intel/AMD only, skipping vendor `0x10de`).

### Open gaps from `origin/research`
| Area | Gap to close |
|---|---|
| **GNOME session completeness** | Only bare `gnome-shell --headless --wayland --no-x11` ran. Need `gnome-session` / `gnome-settings-daemon` (or verify what's needed) and **Xwayland** for X11/Electron apps (Chrome, Antigravity, OpenCode, Claude Desktop). |
| **Remote access & browser UI** | Ubuntu's `gnome-remote-desktop` speaks RDP only (no VNC/noVNC). Need port allocation in `env.rc`, an RDP client helper (`d_rdp`), and decision on browser access (RDP-only vs `labwc`+`wayvnc`+noVNC vs Guacamole/IronRDP). |
| **FUSE clipboard crash** | `gnome-remote-desktop-daemon` aborts when `fusermount3` fails unless clients pass `-clipboard`. Need server-side disable or fix so standard RDP clients don't crash the daemon. |
| **Screen-lock & logout lifecycle** | Must prove screen locking is impossible (`org.gnome.desktop.lockdown` + no GDM shield) and Log Out cleanly stops the container (`podman start` recovers). |
| **Headless screenshots & automated tests** | `gnome-screenshot` hangs on Wayland and `org.gnome.Shell.Screenshot` refuses ("Screenshot is not allowed"); `xdotool` is X11-only. Need Wayland-native screenshot and input/readiness checks for `d_test`. |
| **Integration with `main`** | Prototypes hard-coded `/home/ed/shell`, UID `1001`, and plaintext `rdp-pass`. Must align with `main`'s `container/deb/Containerfile`, `USERID`/`USER_UID`/`USER_GID`, `passwd.init` secret lifecycle, `start.sh`, `vnc-pkg`, `d_bind`, `d_commit`, `AGENTS.md`, and `tests/test_env.sh`. |
| **Minor untried questions** | (a) Can GNOME `--headless` drop `mock-logind.py` and use an empty system bus? (b) Does `labwc` + `wayvnc` work cleanly with zero `/dev/dri` (pixman/llvmpipe) on Ubuntu/Fedora/Arch? (c) NVIDIA CDI on DGX Spark. |

---

## 2. Target Architecture

Keep the existing X11 TigerVNC/noVNC images untouched and add Wayland cleanly alongside them rather than replacing X11:

1. **Two complementary Wayland tracks:**
   - **Track A — `gnome-wayland` (Ubuntu 26.04, RDP, amd64 + arm64):** Real GNOME Shell 50+ via `gnome-shell --headless` + `gnome-remote-desktop-daemon --headless` over RDP. Gives full modern GNOME on Ubuntu 26.04 (where GNOME Shell dropped X11) with zero host setup (CPU) and automatic Intel/AMD GPU acceleration when a Mesa render node is passed.
   - **Track B — `labwc` (Ubuntu / Fedora / Arch, VNC + noVNC, amd64 + arm64):** Lightweight Wayland compositor (`WLR_BACKENDS=headless`) + `wayvnc` + `noVNC` (websockify). Reuses the exact existing VNC/noVNC browser workflow (`d_vnc`, `d_novnc`), supports `grim` screenshots and `wtype` input natively, and serves as a fast, low-overhead Wayland baseline (plus optional Mesa render-node acceleration).
   - **Track C — Omarchy (`container/omarchy/`, deferred/optional):** Keep separate until Tracks A & B prove the shared Wayland plumbing and GPU helper in `env.rc`; revisit once Omarchy ships aquamarine ≥ 0.16 (dropping the two startup workarounds).

2. **Layering in `container/`:**
   - Keep `base` shared across X11 and Wayland (nested podman, CLI tools, `vnc-pkg`, `start.sh`).
   - Either:
     - **Option 1 (simplest):** Build `container/gnome-wayland/Containerfile` and `container/labwc/Containerfile` on `base` (or on a new `wayland` base stage in `container/deb/Containerfile` that adds `dbus`, `mesa`/EGL, `xwayland`, Chrome with `--ozone-platform-hint=auto`, and `cli-installers/` without pulling TigerVNC).
     - **Option 2:** Build on `browser` initially for fastest prototyping (already has Chrome, fonts, `cli-installers/`, noVNC/websockify), then split out a clean `wayland-browser` stage once stable if image size matters.
   - *Recommendation:* Start with **Option 2** (build on `browser`, overriding `/usr/local/bin/vnc-session` or adding a Wayland entrypoint branch in `start.sh`) to validate end-to-end quickly, then decide whether a dedicated `wayland` stage is worth the extra layer.

3. **Secret & runtime conventions (matching `main`):**
   - **Passwords:** Reuse the `passwd.init` pattern — never pass RDP/VNC passwords in container env. For `gnome-wayland`, `start.sh` (or `wayland-start.sh`) reads `rdp-pass.init` (mode 600), configures `grdctl --headless rdp set-credentials "$USER" ...` before starting `gnome-remote-desktop-daemon`, and deletes `rdp-pass.init`. For `labwc`/`wayvnc`, configure `wayvnc` auth (or TLS/VNC password) from `passwd.init` instead of passwordless access.
   - **GPU opt-in in `env.rc`:** Add `d_dri_render=` (default empty = CPU). When set to `auto`, inspect `/sys/class/drm/renderD*/device/vendor` and pick the first non-NVIDIA (`!= 0x10de`) Mesa render node; when set to a path like `/dev/dri/renderD128`, pass `--device "$node" --group-add keep-groups`. Never pass `/dev/dri/card*` or all of `/dev/dri`.
   - **Ports in `env.rc`:** Respect `d_bind`. For `gnome-wayland`, allocate an RDP port range (e.g. `7450+N` → container `3389`, avoiding `7100` reserved for omarchy and existing `6900–7449` blocks) and add a `d_rdp` helper (`xfreerdp3` / `wlfreerdp`). `labwc` can share the standard distro VNC/noVNC ports (`6900+N` / `6080+N`).

---

## 3. Phased Execution Plan

### Phase 1 — Validate open technical questions in nested podman (no `env.rc` changes yet)
1. **GNOME `--headless` session & Xwayland check (Ubuntu 26.04, CPU):**
   - Test whether `gnome-shell --headless --wayland` (with Xwayland enabled, dropping `--no-x11`) starts cleanly and runs both native Wayland Chrome (`--ozone-platform=wayland`) and an X11/Electron test app (`xterm`, `antigravity` or `google-chrome` over Xwayland).
   - Test whether `mock-logind.py` is strictly required or if an empty private system bus suffices without errors/timeouts.
   - Check how to prevent the `gnome-remote-desktop` FUSE clipboard abort (`fusermount3: Permission denied`): test disabling clipboard redirection via gsettings/config or whether `/dev/fuse` (already passed by `d_run`!) makes `fusermount3` succeed inside a normal `d_run` instance.
   - Test screen-lock prevention (verify `org.gnome.ScreenSaver.Lock` / `Super+L` cannot lock) and Log Out (verify ending the session exits `gnome-shell` and stops the container).
   - Solve headless screenshots on GNOME Wayland (evaluate PipeWire/`gst-launch`, `xfreerdp3` frame capture, or `dbus`/portal options).
2. **`labwc` + `wayvnc` + `noVNC` smoke test (Ubuntu 26.04, zero `/dev/dri`):**
   - Test `WLR_BACKENDS=headless WLR_RENDERER=pixman` (and llvmpipe) with `labwc` + `wayvnc -r` + `websockify` + `grim` + `wtype` + `xwayland` inside a throwaway nested Ubuntu `browser` container.
   - Verify `noVNC` connects in a browser, cursor is visible, Chrome renders, `grim` saves a PNG, and exiting `labwc` stops the container.
3. **Optional (from `debian13-vkms-gemini.md`):** Quick check of whether `labwc` pixman works as a zero-GPU baseline across Debian/Fedora too.

### Phase 2 — Build `labwc` Wayland desktop (Track B: VNC/noVNC-native)
- Create `container/labwc/Containerfile` (stage `ubuntu`, expandable to `fedora` / `archlinux`).
- Install `labwc`, `wayvnc`, `wlr-randr`, `grim`, `wtype`, `xwayland`, `foot` (or `xterm`), minimal `/etc/xdg/labwc/rc.xml` + `menu.xml` (Terminal, Chrome, Exit).
- Add a clean `wayland-vnc` entrypoint/session script that starts `dbus-launch`, `labwc`, `wayvnc -r`, and `websockify` (listening on `[::]:6080` → `127.0.0.1:5900`), exiting when any dies.
- Wire `labwc` into `env.rc` (`d_targets_ubuntu`, `d_descs`), `tests/screenshot.sh` (`grim` branch), and `tests/test_env.sh`.
- Verify end-to-end with `d_test` (including nested podman, `vnc-pkg`, `sudo -n true` refused, no `VNC_PASSWORD` leak, screenshot, lock check, logout + `podman start`).

### Phase 3 — Build `gnome-wayland` desktop (Track A: Ubuntu GNOME Shell 50 over RDP)
- Create `container/gnome-wayland/Containerfile` (stage `ubuntu`, amd64 + arm64) installing `gnome-shell`, `gnome-remote-desktop`, `pipewire`, `wireplumber`, `xwayland`, `gnome-terminal`, `nautilus`, `openssl`, and `mock-logind.py` (if Phase 1 confirms it is needed).
- Create a parameterized, root-free session launcher (`/usr/local/bin/wayland-gnome-session` — no hard-coded `ed` or `1001`, uses `$USER` / `$(id -u)` and `$XDG_RUNTIME_DIR`):
  - Generates per-home self-signed TLS cert in `~/.config/vnc-desktop/rdp-tls.{crt,key}` on first boot.
  - Consumes `rdp-pass.init` (mode 600) → `grdctl --headless rdp set-credentials` → deletes `rdp-pass.init`.
  - Applies GSettings defaults (`org.gnome.desktop.remote-desktop.rdp.headless enable true`, `disable-lock-screen=true`, `lock-enabled=false`, `idle-delay=0`, `always-show-log-out=true`, trimmed dash favourites).
  - Supervises `dbus-daemon` (private system bus), optional `mock-logind.py`, `pipewire`, `wireplumber`, `gnome-shell`, and `gnome-remote-desktop-daemon --headless`; exits when the shell or RDP daemon exits.
- Wire into `env.rc`: RDP port mapping (respecting `d_bind`), `d_rdp` helper, `d_test` RDP readiness + screenshot checks, and unit tests in `tests/test_env.sh`.
- Test on both **amd64** (CPU + optional Intel `renderD128`) and **arm64** (DGX Spark CPU).

### Phase 4 — Optional GPU pass-through (`d_dri_render`) & agent desktop compatibility
- Add opt-in `d_dri_render` support to `env.rc` (`auto` for Mesa Intel/AMD only, or explicit `/dev/dri/renderD*`), with unit tests in `tests/test_env.sh`.
- Verify GPU rendering on `hwd23` (`renderD128`, 2× concurrent instances, `drm-engine-render` activity, host desktop unaffected).
- Test agent desktops (e.g. `gnome-wayland-antigravity` or `labwc-opencode`) over Wayland/Xwayland (`--ozone-platform-hint=auto` / `--no-sandbox`).
- Separately (host-only, DGX Spark): investigate NVIDIA Container Toolkit CDI (`--device nvidia.com/gpu=all`) with rootless podman if GPU acceleration on arm64 is wanted.

### Phase 5 — Docs, gallery, and polish
- Update `README.md`, `AGENTS.md`, `docs/README.md` (screenshots), and `.agents/skills/` (`add-desktop`, `nested-testing`) for Wayland targets, RDP ports, and `d_dri_render`.
- Ensure `shellcheck` (0 warnings) and `tests/test_env.sh` pass in CI.

---

## 4. Host / Hardware Matrix

| Host | Arch | GPU | Recommended Wayland path | Notes |
|---|---|---|---|---|
| `hwd23` | amd64 | Intel UHD 770 (`renderD128`) + NVIDIA RTX 4090 (`renderD129`) | `gnome-wayland` or `labwc`, CPU or `d_dri_render=/dev/dri/renderD128` | Multiple instances share `renderD128`; never pass `card1` or `renderD129`. |
| `DGX Spark` | arm64 | NVIDIA GB10 (`renderD128`, no Mesa driver) | `gnome-wayland` or `labwc` (CPU/llvmpipe) | Zero host setup; NVIDIA CDI is a separate Phase 4 investigation. |
| Headless Linux / Debian 13 (`hwd4`) | amd64/arm64 | None / no `vkms` | `gnome-wayland` or `labwc` (CPU/llvmpipe) | Works with no `/dev/dri` and no `vkms` kernel module. |

---

## 5. Resuming

To start execution on this branch (`research/wayland`):
> Start Phase 1 of `research/wayland/PLAN.md`: run the GNOME Wayland (Xwayland, FUSE clipboard, screenshot, mock-logind necessity) and `labwc`+`wayvnc` smoke tests in throwaway nested Ubuntu containers, and record the results here.
