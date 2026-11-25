# Intel iGPU (UHD 770) for Omarchy and GNOME on Wayland

Status: **done** (2026-11-22). Tested in throwaway containers nested in cc1u, which has
only `renderD128`. Both desktops render on the iGPU, and two instances of each ran at once.
GNOME needs nothing new. Hyprland can't use a bare render node, but it works nested in a
headless labwc (prototype: `omarchy-gpu-session.sh`). **Omarchy render-node mode**:
`o_render=1` in `../container/omarchy/` (see its README). **GNOME over RDP** with the GPU:
`../wayland/` (`MODE= headless.sh` + `rdp-headless.sh`, see its README).

### Device decision (2026-11-22)

- **Pass only `renderD128`.** Drop `card2`/`card0` (vkms) and `renderD129` (NVIDIA) from
  this instance. On the host, `logs/env.host`'s `d_run_opts_all_dri` passed all three
  together. Without the NVIDIA host driver's exact userspace, `renderD129` is no use and
  only adds risk (see Caveats).
- **The vkms/Omarchy comparison** can come later, from an instance that has `card2` only.
- **Device numbers have changed since** (seen in `/sys/class/drm` on 2026-11-22): `card0` is
  vkms, `card1` the Intel iGPU (`0000:00:02.0`, with the host's DP/HDMI connectors),
  `card2` the NVIDIA card. `renderD128` is still the Intel one.

## Question

Can the host's Intel iGPU (Raptor Lake-S UHD 770, SR-IOV capable) be used for the
Wayland desktops: Omarchy/Hyprland in `../container/omarchy/` and GNOME Shell in `../wayland/`?
Background: the Hyprland wiki's *Virtual GPU* page
(<https://wiki.hypr.land/configuring/extra/virtual-gpu/#running-hyprland-on-vgpu>) describes
SR-IOV vGPUs for VMs.

## Answer (tested 2026-11-22)

Yes for both. SR-IOV isn't needed, but **Hyprland can't use a render node alone**: it
needs a parent compositor.
- **SR-IOV is for VMs.** These images are containers, which share the host kernel and its
  i915 driver, so a container can use the iGPU's **render node** directly.
  - SR-IOV is there (`sriov_totalvfs` 7, `sriov_numvfs` 0) but only matters for VMs.
- **Many instances, one GPU.** A render node has no DRM master, so any number of containers
  can render on it at once. Seen: two GNOME Shells, and separately two labwc + Hyprland
  pairs, each in its own container, all at the same time on `renderD128`.
- **GNOME Shell 50** (`--headless`): mutter finds the render node by itself (`Added device
  '/dev/dri/renderD128' (i915) using no mode setting`, `Created gbm renderer`), and cogl
  reports `GL_RENDERER: Mesa Intel(R) Graphics (RPL-S)`, `GL_VERSION: 4.6 (Core Profile)
  Mesa 26.0.8`. No changes to `../wayland/headless.sh`, just `--device`.
- **Hyprland 0.56.2 / aquamarine 0.15.1 on a bare render node: no.** `CBackend::create()
  failed!` (the message is the same when `start()` fails, which is what happens here).
  From aquamarine's source:
  - the DRM backend enumerates only `card[0-9]*` nodes (`enumDRMCards`, sysname
    `DRM_PRIMARY_MINOR_NAME`); `AQ_NO_KMS_REQUIREMENT` only lets it use a *card* node that
    has no KMS outputs (a vGPU VF in a VM has one). A bare `renderD*` is never considered;
  - the headless and null backends have no DRM fd (`drmFD()` returns -1), and `start()`
    takes its GBM allocator from the first backend that has one. So: "Cannot open backend:
    no allocator available";
  - `AQ_BACKENDS` doesn't exist in this version.
  - The wiki's vGPU page is about that VM case. Passing the Intel `card1` instead would
    put the host's monitors in the container (`AQ_NO_KMS_REQUIREMENT` doesn't stop it
    from using the connectors). Not tried, and `o_run`'s guard refuses it.
- **Hyprland nested in a headless wlroots compositor: yes.** labwc runs with
  `WLR_BACKENDS=headless WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128` (EGL driver `iris`, GBM
  buffers with Intel CCS modifiers). Hyprland runs as its client on aquamarine's Wayland
  backend, which opens the render node from labwc's dmabuf feedback (`zwp_linux_dmabuf_v1:
  Got node /dev/dri/renderD128`, `Created a GBM allocator`). Hyprland's log says `Vendor:
  Intel`, `Renderer: Mesa Intel(R) Graphics (RPL-S)`. wayvnc runs on labwc. Through it,
  typing over RFB reached a foot terminal inside Hyprland (two compositors deep).
  Hyprland's monitor takes the size of labwc's maximized window (wlr-randr sets labwc's
  output to `$VNC_RESOLUTION`).
  - **Parent: labwc**, because aquamarine binds `xdg_wm_base` **v6** unconditionally. sway
    1.12 and weston 15 offer v5 (protocol error "invalid version for global xdg_wm_base");
    labwc 0.20.2 offers v6. cage wasn't probed (same wlroots 0.20, but each compositor
    picks its own version).
  - **Two aquamarine startup bugs**, both worked around in the prototype:
    1. The Wayland output's first `wl_surface.commit` isn't flushed, and its `newOutput`
       is queued in a list that is only drained when the parent sends something. A quiet
       headless parent sends nothing, so Hyprland sits with no monitor until some event
       arrives (a VNC client connecting did it; so does `wtype -k Shift_L` on labwc,
       whose virtual keyboard changes the seat's capabilities). A labwc output mode
       change does not: aquamarine doesn't bind `wl_output`.
    2. aquamarine emits the first frame from the `xdg_toplevel.configure` handler, before
       it acks the `xdg_surface.configure` that follows. When Hyprland already has the
       monitor at that point, it commits a buffer first and labwc kills the connection
       (`wl_display.error … "xdg_surface has never been configured"`; labwc logs only
       "error in client communication"). Workaround: start with `monitor = WAYLAND-1,
       disable`, nudge (1.), then enable it (config edit + `hyprctl reload`;
       `hyprctl keyword monitor` doesn't re-enable a disabled monitor).
- **Smaller findings**
  - Arch's `sway` has `cap_sys_nice=ep` file caps, outside a nested container's bounding
    set: exec fails with "Operation not permitted". labwc has none.
  - Omarchy's config sets `debug:disable_logs` (default on), and on an abort the log file is
    lost. To debug, use the bare config with `debug { disable_logs = false }`, or
    `hyprctl rollinglog`.

## DGX Spark (arm64, NVIDIA only): the results don't carry over

The user's other host, a DGX Spark, has no Intel or AMD GPU (from `logs/dgx-spark-dri.log`
in the main checkout, 2026-11-22, kernel `7.0.0-1025-nvidia`, aarch64, after `modprobe vkms`):
- `card0` and `renderD128` are the NVIDIA GB10 (`000f:01:00.0`, PCI ID `10de:2e12`, driver
  `nvidia`, modules `nvidia`, `nvidia_drm`); `card1` is vkms. The same names mean other
  devices than on hwd23: there `renderD128` is the Intel iGPU, here the NVIDIA node.
- A normal Ubuntu `gnome` (Flashback) instance with Claude Code ran there (2026-11-20),
  as everywhere else: Xvnc, rendered on the CPU, no `/dev/dri` needed.
- **Omarchy**: not possible on the Spark at all, with or without `o_render`. The rootfs
  comes from the x86 ISO, and Arch Linux is amd64-only in this repo.
- **vkms** works there too: `card1`, and `o_run`'s vkms lookup would find it. But the only
  vkms user here is Omarchy, which is amd64 only. GNOME's KMS mode (`../wayland/kms.sh`)
  is the exception: it **works** on the Spark (2026-11-22), as on hwd23, rendered on the
  CPU (Mesa gallium, llvmpipe), 1024x768, over RDP with mouse input. `fake-run.sh` found
  `card1` by itself; mutter opened only `/dev/dri/card1`. Details in
  [dgx-spark-gnome-vkms.md](dgx-spark-gnome-vkms.md).
- **GNOME `--headless`** (Ubuntu, arm64) runs without any GPU (llvmpipe): tested
  2026-11-22, with no `/dev/dri` in the instance, both RDP ways, Chrome as a Wayland
  client ([dgx-spark-gnome-vkms.md](dgx-spark-gnome-vkms.md), "Headless mode"). On the NVIDIA
  render node, Ubuntu's Mesa has no driver: the container needs NVIDIA's userspace for
  the host driver's exact version (GL/EGL libraries, the GBM backend
  `nvidia-drm_gbm.so`, the EGL vendor files). The usual way is the NVIDIA container
  toolkit's CDI (`--device nvidia.com/gpu=all`, graphics capability), which mounts the
  host's libraries so the versions match. DGX OS normally ships the toolkit.
- Not verified:
  - what mutter does with an nvidia-drm render node and no NVIDIA GBM library
    (software fallback or failure);
  - whether CDI works with rootless podman there;
  - how a nested instance would get the libraries from its outer instance.
- So `--device /dev/dri/renderD128` mustn't go into a shared `d_run_opts` that both hosts
  use: on the Spark it passes the NVIDIA node.

## Prerequisite (on the host)

The instance where this runs needs the render node: add
`--device /dev/dri/renderD128 --group-add keep-groups` to `d_run_opts` in the host's
`.env` (and nothing else under `/dev/dri`), then recreate the instance (now cc1u; it
was cc8u). That stops everything nested in it and any Claude session running there.
Also check `ls /dev/dri` shows only `renderD128`.

Check in the instance:
```bash
ls -l /dev/dri/renderD128
podman run --rm --security-opt label=disable --userns=keep-id \
    --device /dev/dri/renderD128 --group-add keep-groups localhost/u2604cc:base \
    bash -c 'exec 3<>/dev/dri/renderD128 && echo OPEN-OK'
```

## What was run

All nested in cc1u, in throwaway containers (`--device /dev/dri/renderD128 --group-add
keep-groups`, no other `/dev/dri` node):
- `omarchy:omarchy` built with `o_build omarchy` (unchanged), and `omarchy:gputest` = that
  image + `sway cage strace labwc weston wayland-utils wlr-randr` (pacman as root,
  `podman commit`). `omarchy-gpu-session.sh` is the prototype that ran in two of them at
  once (bare Hyprland config, foot).
- `u2604cc:gstest` = `u2604cc:base` + `gnome-shell python3-dbus python3-gi mesa-utils
  dbus-x11` (apt as root, `podman commit`), running `../wayland/headless.sh` with `MOCK=1`.
  `COGL_DEBUG=winsys,driver` prints the GL strings; `MUTTER_DEBUG=backend,render` shows the
  device choice.
- Later (see "Next"): Omarchy's own desktop on this path, GNOME over RDP with the GPU.
  Not done: the host side (the host desktop was not watched during the tests).

## Next

1. ~~**Omarchy render-node mode**~~ **done** 2026-11-22: `o_target=omarchy o_render=1
   o_run N`, two Omarchy desktops at once at 1440x900 over wayvnc/noVNC. What changed
   from the prototype:
   - wayvnc talks to Hyprland, not to labwc. labwc gets no input, and `o_screenshot` and
     `o_exec` work as before.
   - Re-enabling goes through `hyprctl reload`. A later `hl.monitor` eval doesn't
     re-enable a disabled output, even with `disabled = false`. On a first boot an
     Omarchy reload hid this; on a restart the output stayed disabled ("No such output"
     from wayvnc).
   - New homes get `omarchy_monitor_scale = 1` (`"auto"` picked 2).
   - The session waits for the output to be active before starting wayvnc.
2. ~~**GNOME**~~ **done** 2026-11-22. With the render node, the full Shell shows over RDP
   and a click went through. gnome-shell gains i915 render time as the screen changes;
   gnome-remote-desktop encodes on the CPU (no render-node fd). This used gnome-remote-
   desktop's **headless** mode (`../wayland/rdp-headless.sh`): a virtual monitor per
   client and credentials in a file, no keyring. Run the shell with no monitor of its own
   (`MODE= headless.sh`), or the client sees a second, empty monitor.
3. ~~Results into the READMEs~~ **done** (`../container/omarchy/README.md`, `../wayland/README.md`).
4. ~~Report the aquamarine bugs upstream~~: draft in
   [aquamarine-upstream-draft.md](aquamarine-upstream-draft.md), **not submitted**. Both
   startup bugs are already fixed in aquamarine v0.16.0. The fixed-version binds are
   issue #398, closed as not planned.

## Caveats

- **Throughput**: the GPU renders, but wayvnc/RFB (and RDP) still copy and encode frames
  on the CPU. That's still a large gain over llvmpipe for compositing and Chromium.
- **Shared GPU**: the iGPU is shared with the host desktop; a GPU hang could affect both.
- **NVIDIA `renderD129`** (hwd23's RTX 4090; on the DGX Spark the NVIDIA node is
  `renderD128`): possible in principle, but the container needs the host driver's exact
  userspace (see the DGX Spark section). Not tried.
- **SR-IOV VFs**: only if this is ever wanted inside VMs. They need host i915 SR-IOV support
  and firmware; not needed for containers.
- **Two compositors for Omarchy**: labwc composites Hyprland's output once more (one
  extra GPU blit per frame), and the aquamarine workarounds depend on its current
  behaviour: recheck after a Hyprland/aquamarine update.

## Verification

- In each instance: the renderer string shows Intel/iris, not llvmpipe. **Done** for GNOME
  and for bare Hyprland + labwc.
- Two instances run at once. **Done** (2× GNOME, 2× labwc+Hyprland, 2× Omarchy desktop
  over wayvnc/noVNC).
- The host desktop is unaffected: not watched yet.
- `podman inspect` shows only `renderD128` (plus a vkms card when testing vkms).

## Resuming

After the prerequisite, ask Claude Code (in the repo):
> Continue research/intel-igpu-render-node.md

It should:
1. Confirm `/dev/dri/renderD128` is visible and opens from a nested container.
2. Everything under "Next" is done; the upstream report is a draft for the user (the
   test image `u2604cc:gstest`, gnome-shell + gnome-remote-desktop, may still be in cc1u's
   nested storage).
3. Update this file's Status line as it goes.
