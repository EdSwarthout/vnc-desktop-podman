# Wayland Desktops in Rootless Podman — Merged Plan

Status: **Phases 1–3 and 5 implemented and verified on nested amd64; Phase 4 `d_dri_render` implemented (host GPU & arm64 tests remaining)** (2026-11-26, branch `research/wayland-agy`, based on `origin/research/wayland` at `048298c`).
Inputs: `origin/research-20261117` (`3307cbf`), [PLAN.md](PLAN.md), [PLAN-cc.md](PLAN-cc.md), [PLAN-cc-2.md](PLAN-cc-2.md).

---

## 1. Review of `research-20261117`

### Proven and worth keeping
- **GNOME Shell 50.1 (`--headless --wayland`)** runs without systemd on both amd64 (`hwd23`) and arm64 (`DGX Spark`) with no `/dev/dri`, no root, and no host setup. Needs a private per-user system bus (`system-bus.conf`) and `mock-logind.py` (`python3-dbus`, `python3-gi`) for a clean start ("Failed to start state machine" without it). Unlimited concurrent instances.
- **Intel Mesa render node** (`--device /dev/dri/renderD128 --group-add keep-groups` on `hwd23`) is used automatically by mutter (`Created gbm renderer`, Mesa `iris`, GL 4.6) with multiple concurrent shells on one GPU.
- **`gnome-remote-desktop` (RDP)** works in both **mirror mode** (`rdp.sh`, mirrors the Shell's virtual monitor, credentials in keyring) and **headless mode** (`rdp-headless.sh`, separate monitor per client, `credentials.ini`). Chrome (`--ozone-platform=wayland`) and mouse input work on amd64 and arm64.
- **Known `grd` workarounds:** `grdctl … enable` requires systemd, so enable via `gsettings` instead; set credentials *before* starting the daemon (`SEC_E_MESSAGE_ALTERED` otherwise); `fusermount3` clipboard failure aborts the daemon unless clients pass `-clipboard`.
- **`labwc` + `wayvnc -r` + `noVNC`** runs headless on CPU or Mesa render node, has no nested-breaking file caps (unlike Arch's `sway` with `cap_sys_nice=ep`), and speaks standard VNC/noVNC.

### Drop / out of scope
- **GNOME KMS on `vkms` (`kms.sh`, `fake-run.sh`):** Works on amd64 (`card0`) and arm64 (`card1`), but adds host `modprobe vkms`, root `/run` fakes, fixed 1024×768, and a 1-instance-per-card DRM master limit while still rendering on the CPU. Drop for GNOME.
- **Omarchy (`container/omarchy/`):** Standalone (`o_*`), amd64-only (7.5 GB x86 ISO btrfs rootfs), depends on aquamarine 0.15.1 workarounds (fixed in v0.16.0). Leave on `research-20261117` until Wayland plumbing is settled.

### Prototype issues to fix during integration
- Remove hard-coded `/home/ed/shell`, UID `1001` (including `<listen>` in `system-bus.conf`), plaintext `rdp-pass`, and old `u2604cc:*` names. Package everything cleanly in Containerfiles on top of `main`'s `deb/`, `USERID`/`USER_UID`/`USER_GID`, `vnc-pkg`, `d_bind`, `d_commit`, and `tests/test_env.sh`.
- Close untested areas: Xwayland, `gnome-session` vs `gsd-*` daemons on GNOME 50, screen-lock prevention, Log Out stopping the container, screenshots, `wayvnc` auth with `noVNC`/`vncviewer`, and `d_test` integration.

---

## 2. Target Design

Add two Ubuntu 26.04 Wayland desktops built on `browser` (amd64 + arm64, CPU rendering by default; opt-in Mesa GPU render node in Phase 4). Both target names are **hyphen-free** because `env.rc`'s `_d_distro` parses every `X-Y` target as desktop `X` + agent `Y` (`_d_layer=${d_target##*-}`). Because of that, agent desktops like `gnomewl-opencode` and `gnomewl-antigravity` will also work with no `env.rc` parser changes.

| | `gnomewl` (GNOME Shell 50, Wayland) | `labwc` (wlroots, Wayland) |
|---|---|---|
| Containerfile | `container/gnomewl/Containerfile` (stage `ubuntu`) | `container/labwc/Containerfile` (stage `ubuntu`; Fedora/Arch later) |
| Compositor | `gnome-shell --headless --wayland --virtual-monitor $VNC_RESOLUTION` + private system bus + `mock-logind.py` | `labwc` (`WLR_BACKENDS=headless`, `WLR_RENDERER=pixman` or `gles2`/llvmpipe) + `wlr-randr` |
| Remote access | **Bridge:** Xvnc `:1` as today; `vnc-session` runs full-screen `xfreerdp3 /from-stdin` to mirror-mode `grd` on `127.0.0.1:3389`. Optional external RDP: `d_rdp=1` → `7450+N:3389` | `wayvnc -r` on `0.0.0.0:5901` via `/usr/local/bin/vnc-wayland` in place of `vncserver`, reusing `websockify`/noVNC on `6080` |
| Ports | Ubuntu's `6900+N` / `6080+N`; optional RDP `7450+N` (`d_rdp=1`, respects `d_bind`) | Ubuntu's `6900+N` / `6080+N` (respects `d_bind`) |
| Screenshot | `scrot` on `:1` (captures the bridge showing the Shell) | `grim` |

### `gnomewl` session (`/usr/local/bin/vnc-session`)
Runs under `xstartup` + `dbus-launch` on Xvnc `:1`, so `start.sh` keeps its normal VNC startup:
1. Start private system `dbus-daemon` at `$XDG_RUNTIME_DIR/system_bus_socket` (`--address` only, no hard-coded UID) and `/usr/local/libexec/vnc-desktop/mock-logind.py`.
2. Start `gnome-shell --headless --wayland --virtual-monitor "${VNC_RESOLUTION:-1440x900}"` with `DISPLAY` unset so it does not collide with Xvnc `:1` and Xwayland is enabled (no `--no-x11`), plus whichever `gsd-*` daemons Phase 1 confirms are needed.
3. Ensure a passwordless default keyring exists (reuse `container/claude/`'s `Default_keyring.keyring` + `default` writer when absent) and generate a self-signed TLS cert once in `~/.config/vnc-desktop/rdp-tls.{crt,key}`.
4. **RDP password (never in container env or argv):** During first boot in `start.sh`, if `gnome-remote-desktop` is installed, also write `~/.config/vnc-desktop/rdp-pass` (mode `600`) from `passwd.init` (matching the VNC password); if `passwd.init` is absent (nested run copying parent's `passwd`), generate a random one. `vnc-session` loads it via `grdctl rdp set-credentials "$USER"` before starting `gnome-remote-desktop-daemon`, and passes it to `xfreerdp3` via `/from-stdin`.
5. Start `pipewire`, `wireplumber`, and **mirror-mode** `gnome-remote-desktop-daemon` so the Xvnc bridge and any external `d_rdp=1` client see the same screen (like VNC `-Shared`; headless `grd` would give them separate monitors).
6. Foreground loop: run `xfreerdp3 /v:127.0.0.1 /u:"$USER" /f -clipboard /cert:ignore /auto-reconnect /from-stdin` while `gnome-shell` is alive (restarting `grd` if it exits). When `gnome-shell` exits (Log Out), terminate helpers and exit so `vncserver` and the container stop cleanly.
7. Export `WAYLAND_DISPLAY`, Xwayland's `DISPLAY`, and `DBUS_SYSTEM_BUS_ADDRESS` in the session process environment so `d_exec -s` launches apps inside GNOME Shell, not behind the bridge on `:1`.
8. GSettings override (`/usr/share/glib-2.0/schemas/99_vnc-desktop.gschema.override`, compiled with `--strict`): `disable-lock-screen=true`, `lock-enabled=false`, `idle-delay=uint32 0`, `always-show-log-out=true`, trimmed dash favourites (Chrome, Files, Terminal), and RDP `enable=true`, `view-only=false`.

### `labwc` session (`/usr/local/bin/vnc-wayland`)
- `start.sh` adds one branch: if `/usr/local/bin/vnc-wayland` is executable, run it in place of `vncserver :1 -fg …`, leaving `websockify`/noVNC (`127.0.0.1:5901`) unchanged.
- `vnc-wayland` (bash, matching `vncserver-wrapper`'s lifecycle contract): starts `dbus-launch`, headless `labwc` + `wlr-randr --custom-mode "$VNC_RESOLUTION"`, and `wayvnc -r 0.0.0.0 5901`; exits when either `labwc` or `wayvnc` ends. Its non-`wayvnc` child is the session process.
- Packages: `foot`, `grim`, `labwc`, `swaybg`, `wayvnc`, `wlr-randr`, `wtype`, `xwayland`, plus minimal `/etc/xdg/labwc/{rc.xml,menu.xml}` (Terminal, Chrome, Exit).
- **Auth caveat:** `wayvnc` does not support classic password-only `VncAuth` — it uses RSA-AES or TLS with username + password. Configure `~/.config/wayvnc/{config,rsa_key.pem}` from `passwd.init` on first boot (keeping `~/.config/tigervnc/passwd` written for `_d_wait_ready`), and verify both `noVNC` and `d_vnc` (`vncviewer`) behavior in Phase 1.

### `env.rc` and `tests/` integration
- `env.rc`:
  - Add `gnomewl` and `labwc` to `d_targets_ubuntu` and `d_descs`.
  - Add `d_rdp_ports0=([gnomewl]=7450)` (free range 7450–7499); when `d_rdp=1` and the target has an entry, `d_run` publishes `-p "${bind}$((7450+N)):3389"`. Add `d_rdp` helper (runs `xfreerdp3` or prints the command using `$d_home/.config/vnc-desktop/rdp-pass`).
  - `_d_session_sh`: also match `/bin/bash /usr/local/bin/vnc-wayland` and ignore `wayvnc` alongside `Xtigervnc|Xvnc`.
  - `d_exec -s`: forward `WAYLAND_DISPLAY` and `DISPLAY` in addition to D-Bus/`XDG_*`/`SHELL`.
  - `_d_wait_ready`: use `grim` readiness check on Wayland-only targets (`labwc`); `gnomewl` keeps `xdotool` (bridge window appears on `:1` once RDP connects).
  - `d_test`'s `session_end`: accept either `vncserver exited` or `vnc-wayland exited`.
- `tests/screenshot.sh`: add a `grim` branch when `WAYLAND_DISPLAY` is set and no X11 screenshot tool applies.
- `tests/lock.sh`:
  - `gnomewl`: trigger `org.gnome.ScreenSaver.Lock` and `Super+L` (via `xdotool` into the bridge), then fail if `org.gnome.ScreenSaver.GetActive` is true or typing into a Shell-side terminal fails.
  - `labwc`: assert no `ext-session-lock` locker is installed/active and verify `wtype` input reaches `foot`.
- Keep `shellcheck` clean (0 warnings) and add coverage in `tests/test_env.sh` (`d_rdp`, `d_rdp_ports0`, `gnomewl`/`labwc` targeting, `d_dri_render`).

---

## 3. Phased Execution Plan

### Phase 1 — Answer open questions in throwaway nested Ubuntu instances (**DONE** 2026-11-26, amd64)
All 6 items verified in throwaway nested Ubuntu 26.04 instances (`browser` and `gnome` stages, zero `/dev/dri`):
1. **GNOME Xwayland & `DISPLAY`:** Confirmed. Starting `gnome-shell --headless --wayland --virtual-monitor 1440x900` with `DISPLAY` unset spawns Xwayland on `:0` (while Xvnc holds `:1`) and writes `$XDG_RUNTIME_DIR/.mutter-Xwaylandauth.XXXXXX`. Passing `DISPLAY=:0 XAUTHORITY="$xauth"` lets X11 clients (`xterm`) connect cleanly (`GNOME-XWAYLAND-AUTH-OK`). Because `gnome-shell` creates `wayland-0` and `.mutter-Xwaylandauth.*` after startup, `vnc-session` writes `$XDG_RUNTIME_DIR/session.env` so `d_exec -s` picks up `WAYLAND_DISPLAY`, `DISPLAY`, and `XAUTHORITY`.
2. **`gnome-session` vs `gsd-*`:** Confirmed `gnome-session` 50.1 removed `--builtin` (`Unknown option --builtin`) and requires systemd. Starting `/usr/libexec/gsd-xsettings` (with Xwayland `DISPLAY`/`XAUTHORITY`) and `/usr/libexec/gsd-keyboard` directly works cleanly (11 threads, ~20 MB RSS combined).
3. **`mock-logind.py`:** Kept (1 thread, 27 MB RSS); gives clean `gnome-shell` startup with no login1 state-machine errors.
4. **Bridge + mirror-mode `grd` + FUSE clipboard:**
   - Exact `xfreerdp3` stdin flag is `/from-stdin:force` (plain `/from-stdin` fails NLA auth). Full-screen `1440×900` GNOME Shell 50.1 rendered cleanly on `:1` and captured via `scrot`.
   - Connecting a 2nd simultaneous `xfreerdp3` client to mirror-mode `grd` kept the bridge alive (shared view confirmed).
   - `org.gnome.desktop.remote-desktop.rdp` has no server-side clipboard disable key. Even with `--device /dev/fuse`, `fusermount3: mount failed: Permission denied` still aborts `gnome-remote-desktop-daemon` when a client connects with `+clipboard`. Solution: bridge and `d_rdp` pass `-clipboard`, and `vnc-session` supervises and auto-restarts `grd` if an external `+clipboard` client crashes it; the container stops only when `gnome-shell` exits.
5. **Lock & Log Out:** `org.gnome.ScreenSaver.Lock` and `GetActive` both return `ServiceUnknown: The name org.gnome.Shell.ScreenShield was not provided` (no GDM = no screen shield; locking is impossible). Add `vnc-logout.desktop` (`pkill -x gnome-shell`) alongside `always-show-log-out=true` since `gnome-session` isn't running.
6. **`labwc` + `wayvnc` auth (zero `/dev/dri`):**
   - All packages exist in Ubuntu 26.04: `labwc` 0.9.3, `wayvnc` 0.9.1 (`neatvnc` 0.9.1), `wlr-randr` 0.4.1, `grim` 1.4.0, `wtype` 0.4, `foot` 1.25.0, `xwayland` 24.1.10, `swaybg` 1.2.1.
   - `WLR_RENDERER=gles2` fails without `/dev/dri` (`no DRM FD available`); **`WLR_RENDERER=pixman` works cleanly**: `wlr-randr` sets `1440×900`, `grim` saves crisp PNGs, `foot` + `wtype` works, Xwayland starts on `:0` (`XWAYLAND-OK`), and native Wayland Chrome renders cleanly.
   - **Auth finding:** `wayvnc` 0.9.1 with `enable_auth=true` requires a traditional PKCS#1 RSA key (`openssl genrsa -traditional`, not OpenSSL 3's default PKCS#8) and advertises only `[19 (VeNCrypt/TLSPlain), 129 (RA2_256), 5 (RA2)]`. Ubuntu's packaged `noVNC` supports only `None (1)`, `VNCAuth (2)`, `RA2ne (6)`, and `VeNCrypt Plain (256)` — so `noVNC` cannot authenticate when `wayvnc` has `enable_auth=true`. Decision: default `wayvnc` to `enable_auth=false` so `noVNC` and `d_vnc` work out of the box (use `d_bind=127.0.0.1` on untrusted networks), with opt-in `WAYVNC_AUTH=1` enabling RSA-AES auth for native TigerVNC clients.
7. **Resource usage (idle, CPU rendering):**
   - `labwc` + `wayvnc`: **35 threads, ~91 MB RSS**.
   - `gnomewl` (`gnome-shell` + `gsd-xsettings` + `gsd-keyboard` + `pipewire` + `wireplumber` + `grd` + `mock-logind` + `dbus-daemon`): **117 threads, ~440 MB RSS** (plus `Xvnc` + `xfreerdp3` bridge; well below `d_pids_limit=16384`).

### Phase 2 — Implement `labwc` (**DONE** 2026-11-26, amd64 nested)
- Implemented `container/labwc/Containerfile`, `container/vnc-wayland` (`!container/vnc-wayland` in `.containerignore`), `container/start.sh` branch, `env.rc` (`_d_session_sh`, `d_exec -s` via `session.env`, `_d_wait_ready` `grim` fallback, `d_test` `vnc-wayland exited`), `tests/screenshot.sh`, `tests/lock.sh`, and `tests/test_env.sh`.
- Verified: `shellcheck` (0 warnings), `bash tests/test_env.sh` (0 failed), and `d_distro=ubuntu d_test 10 labwc` (**0 failed**, clean screenshot).

### Phase 3 — Implement `gnomewl` (**DONE** 2026-11-26, amd64 nested; arm64 host test pending)
- Implemented `container/gnomewl/{Containerfile,mock-logind.py,vnc-session}`, `container/start.sh` `rdp-pass` seeding, `d_rdp`/`d_rdp_ports0` (`7450+N:3389`, respects `d_bind`) in `env.rc`, `tests/lock.sh` Wayland GNOME checks, and `tests/test_env.sh` coverage.
- Verified on amd64 nested: `d_distro=ubuntu d_test 11 gnomewl` (**0 failed**, crisp GNOME Shell 50 Activities screenshot), `d_rdp=1` port `7461:3389` listening + `xfreerdp3 /from-stdin:force -clipboard /auth-only` handshake succeeded, `d_exec -s` exposes `WAYLAND_DISPLAY`, Xwayland `DISPLAY=:0`, `XAUTHORITY`, and `DBUS_SYSTEM_BUS_ADDRESS` (`xset q` works), and no `rdp-pass` appears in `podman inspect` or `/proc/*/cmdline`/`environ`.
- Remaining host-only check: build and run `d_test` on `DGX Spark` (arm64).

### Phase 4 — Optional vendor-safe GPU pass-through (`d_dri_render`) & agent desktops (**Code implemented; host GPU & agent smoke-tests pending**)
- Implemented opt-in `d_dri_render=` in `env.rc` (default empty = CPU) + unit test in `tests/test_env.sh`:
  - `d_dri_render=auto`: scans `/sys/class/drm/renderD*/device/vendor` and picks the first Mesa render node (Intel/AMD, skipping NVIDIA `0x10de`).
  - `d_dri_render=/dev/dri/renderD128`: passes that explicit render node (`--device "$node" --group-add keep-groups`). Never passes `/dev/dri/card*` or all of `/dev/dri`.
- Remaining host-only checks:
  - Verify 2× concurrent GPU-accelerated instances on `hwd23` (`drm-engine-render` active, host desktop unaffected).
  - Smoke-test `gnomewl-antigravity` / `gnomewl-opencode` (`--ozone-platform-hint=auto` / Xwayland).
  - Separate host-only investigation on DGX Spark: NVIDIA Container Toolkit CDI (`--device nvidia.com/gpu=all`) with rootless podman if GPU acceleration on arm64 is desired.

### Phase 5 — Docs, gallery, and CI (**DONE** 2026-11-26)
- Updated `README.md`, `AGENTS.md`, `.agents/skills/add-desktop/SKILL.md` (no-hyphen target rule, Wayland lock/screenshot checks), `docs/README.md`, `.github/workflows/ci.yml`, and captured `docs/ubuntu/{gnomewl,labwc}.png` via `d_screenshots`.
- Verified local CI checks (`shellcheck` + `bash tests/test_env.sh`) pass cleanly with 0 warnings / 0 failures.

---

## 4. Host / Hardware Matrix

| Host | Arch | GPU | Recommended Wayland path | Notes |
|---|---|---|---|---|
| `hwd23` | amd64 | Intel UHD 770 (`renderD128`) + NVIDIA RTX 4090 (`renderD129`) | `gnomewl` or `labwc`, CPU or `d_dri_render=auto` (`renderD128`) | Multiple instances share `renderD128`; never pass `card1` or `renderD129`. |
| `DGX Spark` | arm64 | NVIDIA GB10 (`renderD128`, no Mesa driver) | `gnomewl` or `labwc` (CPU/llvmpipe) | Zero host setup; `d_dri_render=auto` skips `0x10de`. NVIDIA CDI is a separate Phase 4 task. |
| Headless Linux / Debian 13 (`hwd4`) | amd64/arm64 | None / no `vkms` | `gnomewl` or `labwc` (CPU/llvmpipe) | Works with no `/dev/dri` and no `vkms` kernel module. |

---

## 5. Risks & Tradeoffs
- **GNOME 50 without `gnome-session`:** May miss settings or portal pieces; Phase 1 determines whether `gsd-*` daemons are sufficient.
- **Double encode in `gnomewl` bridge:** `grd` encodes RDP and Xvnc encodes VNC inside the container (extra CPU, no extra network bandwidth). External RDP (`d_rdp=1`) avoids the second encode for native RDP clients.
- **`wayvnc` auth UX:** Username + password (RSA-AES/TLS) differs from TigerVNC's password-only `VncAuth`; Phase 1 checks compatibility with `noVNC` and `d_vnc`.
- **Plaintext keyring / `rdp-pass`:** Mirror-mode `grd` needs the passwordless plaintext keyring and `rdp-pass` (mode `600`); matches the repo's existing "no user password" model and is equivalent in sensitivity to TigerVNC's `passwd` file.

---

## 6. Resuming

> Start Phase 1 of `research/wayland/PLAN-agy-2.md` in throwaway nested Ubuntu instances and record the results in that file.
