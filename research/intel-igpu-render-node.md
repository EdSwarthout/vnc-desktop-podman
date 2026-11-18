# Intel iGPU (UHD 770) for Omarchy and GNOME on Wayland

Status: **planned, not started** (2026-11-17). Waiting on the prerequisite below.

## Question

Can the host's Intel iGPU (Raptor Lake-S UHD 770, SR-IOV capable) be used for the
Wayland desktops: Omarchy/Hyprland in `../omarchy/` and GNOME Shell in `../wayland/`?
Background: the Hyprland wiki's *Virtual GPU* page
(<https://wiki.hypr.land/configuring/extra/virtual-gpu/#running-hyprland-on-vgpu>) describes
SR-IOV vGPUs for VMs.

## Answer (expected; to be confirmed)

Yes, and it's better than vkms. SR-IOV isn't needed:
- **SR-IOV is for VMs.** These images are containers, which share the host kernel and its
  i915 driver, so a container can use the iGPU's **render node** directly.
  - On hwd23, `renderD128` → `0000:00:02.0`, driver `i915`. (`renderD129` is the NVIDIA
    RTX 4090; `card2` is vkms.)
  - SR-IOV is there (`sriov_totalvfs` 7, `sriov_numvfs` 0) but only matters for VMs.
- **Many instances, one GPU.** A render node has no DRM master, so any number of containers
  can render on it at once, next to the host's own desktop. The vkms card allows one
  compositor at a time.
- **Hardware GL.** The compositors run their **headless** backends: no outputs to own, and
  Mesa's iris does the rendering instead of llvmpipe/kms_swrast.
  `AQ_NO_KMS_REQUIREMENT=1` (from the wiki page) is Hyprland's switch for a GPU without
  display outputs. A vGPU and a render node look the same to it.

## Prerequisite (on the host)

The instance where this runs needs the render node. For cc8u: add
`--device /dev/dri/renderD128` to `d_run_opts` (keep `/dev/dri/card2` for comparison)
and recreate cc8u. That stops everything nested in it and any Claude session running
there.

Check in the instance:
```bash
ls -l /dev/dri/renderD128
podman run --rm --security-opt label=disable --userns=keep-id \
    --device /dev/dri/renderD128 --group-add keep-groups localhost/archcc:base \
    bash -c 'exec 3<>/dev/dri/renderD128 && echo OPEN-OK'
```

## Steps

1. **Omarchy (Hyprland)**: a render-node mode in `../omarchy/omarchy-session`, chosen by
   device. Today's vkms path stays as it is.
   - Render node given (`OMARCHY_RENDER=/dev/dri/renderD128`):
     - `AQ_BACKENDS=headless`, `AQ_NO_KMS_REQUIREMENT=1`, `AQ_DRM_DEVICES=$OMARCHY_RENDER`;
     - no libseat needed;
     - after start, create a headless output at `$VNC_RESOLUTION` (`hyprctl output create
       headless`, or `hl.monitor` with the Lua config);
     - wayvnc on that output (`HEADLESS-1`).
   - `../omarchy/env.rc`: an `o_render` option for `o_run` that passes the render node
     instead of the vkms card. Keep the guard: render nodes or vkms only, never a real
     card node.
   - Check:
     - the Hyprland log / `hyprctl systeminfo` names the renderer as iris (Intel), not
       llvmpipe;
     - wayvnc/noVNC show the desktop;
     - **two instances run at once**, which vkms couldn't do.
2. **GNOME Shell** (`../wayland/` experiment): `headless.sh` with the render node passed
   into the nested instance. mutter's `--headless` should pick EGL on the render node.
   - Check the GL renderer in `gnome-shell`'s log (`Mesa Intel(R) Graphics (RPL-S)` vs
     `llvmpipe`).
   - Still viewed over RDP (gnome-remote-desktop) as before. This is the same
     experiment with a GPU, not a new desktop stage yet.
3. Write the results into `../omarchy/README.md` and `../wayland/README.md`: render node
   vs vkms, instances at once, hardware GL, the renderer strings seen.

## Caveats

- **Throughput**: the GPU renders, but wayvnc/RFB (and RDP) still copy and encode frames
  on the CPU. That's still a large gain over llvmpipe for compositing and Chromium.
- **Shared GPU**: the iGPU is shared with the host desktop; a GPU hang could affect both.
- **NVIDIA `renderD129`**: possible in principle, but the image needs the exact host driver
  version's userspace (`nvidia-utils`, its GBM backend). Not worth it now.
- **SR-IOV VFs**: only if this is ever wanted inside VMs. They need host i915 SR-IOV support
  and firmware; not needed for containers.

## Verification

- In each instance: the renderer string shows Intel/iris, not llvmpipe.
- Two Omarchy instances run at once, both viewable over wayvnc/noVNC.
- The host desktop is unaffected.
- `podman inspect` shows only `renderD128` (plus `card2` when testing vkms).

## Resuming

After the prerequisite, ask Claude Code (in the repo):
> Continue research/intel-igpu-render-node.md

It should:
1. Confirm `/dev/dri/renderD128` is visible and opens from a nested container.
2. Go through the steps in order.
3. Update this file's Status line as it goes.
