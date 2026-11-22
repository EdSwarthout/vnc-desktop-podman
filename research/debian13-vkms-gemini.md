# Wayland without vkms: review of a Gemini answer

Status: **reviewed, not tested** (2026-11-22). The Gemini answer is kept unchanged
below the review. It's an AI suggestion, not tested instructions.

## Question

Debian 13's kernel has no `vkms`, and a vkms card holds one compositor at a time.
Is there another way to run the Wayland desktops: GNOME Shell (`../wayland/`) and
Omarchy/Hyprland (`../omarchy/`)?

## Answer (from the review; the tests below are still to run)

- **Gemini answers a different question.** Its setup is *apps as clients of a host
  compositor*: a headless labwc runs on the host, and its socket is bind-mounted into the
  container. GNOME Shell and Hyprland *are* compositors, so they have to run inside the
  container. A compositor on the host would also break this repo's model:
  self-contained instances, one VNC endpoint each, nothing running on the host. The
  socket bind-mount itself (`keep-id`, `label=disable`) would work. It's just not what's
  needed.
- **Prompt 1 isn't answered.** It never says why Debian 13 lacks vkms. Still open: check
  `CONFIG_DRM_VKMS` in a Debian 13 host's `/boot/config-*`.
- **What's useful in it is the compositor's own headless backend:**
  - **GNOME**: already works without vkms. `../wayland/headless.sh` (`gnome-shell
    --headless --virtual-monitor WxH`) is the recommended path in `../wayland/README.md`,
    with any number of instances. Nothing new here; the remaining work is that README's
    "Not done / open" list.
  - **Omarchy (Hyprland)**: this is the gap. wlroots compositors (labwc, sway, cage) can
    run headless on the **pixman** CPU renderer with no `/dev/dri` at all. That's why
    Gemini's recipe works for them. Hyprland has no pixman renderer: Aquamarine
    allocates with GBM/EGL and needs a DRM fd. So "no device" is expected to fail
    (unverified: test 2 below).
- **Errors in it**: "When would you actually need vkms?" lists cage and sway as DRM-only,
  but both have headless backends. In this repo, vkms was needed only for Hyprland and for
  GNOME's KMS mode (`../wayland/kms.sh`).
- **Ways to run Omarchy without vkms, best first:**
  1. **A GPU render node** (`renderD128`, Intel iGPU): see
     [intel-igpu-render-node.md](intel-igpu-render-node.md). It gives hardware GL and
     many instances at once. Gemini's aside about `--device /dev/dri/renderD128` agrees.
  2. **Gemini's idea moved inside the container**: in the image, sway or labwc runs
     headless (pixman) with wayvnc on it, and Hyprland runs as a *nested Wayland client*
     of it (Aquamarine's Wayland backend). Hyprland probably still needs a render node:
     it still renders with EGL, and a pixman parent takes only shm buffers.
  3. **Without a render node** there's still vkms: on Debian 13 that means building the
     module out of tree (DKMS).

## Prerequisites

- An `omarchy:wayvnc` image (`../omarchy/README.md`), run nested in an instance.
- Tests 1 and 2 need no `/dev/dri` device at all, which is the point.

## Steps

1. **Pure headless, no device**: `podman run` the `wayvnc` stage like `o_run`, but
   with no `--device` and `AQ_BACKENDS=headless`. `omarchy-session` refuses to start
   without `/dev/dri/card*`, so start Hyprland by hand (`podman exec` with
   `XDG_RUNTIME_DIR`, `LIBSEAT_BACKEND=noop`, `Hyprland --config
   /etc/omarchy-vnc/hyprland.conf`). Expected: it fails. Record the error lines.
2. **Hyprland nested in a pixman wlroots compositor**: in the same container, as root,
   `pacman -Syu --needed sway` (Omarchy's stable pacman config, as in the
   Containerfile). Then:
   - start `WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway`;
   - start `wayvnc` on it and check that a foot terminal shows up;
   - start `Hyprland` with `WAYLAND_DISPLAY` set to sway's socket.

   Expected: Hyprland fails to get an EGL/GBM device. If it does run, check the
   renderer (llvmpipe?) and whether input reaches it through two compositors.
3. Write the results here, update the Status line and `README.md`'s table, and, if test 2
   works, add a section to `../omarchy/README.md`.

## Resuming

> Continue research/debian13-vkms-gemini.md: run the two steps in a nested omarchy:wayvnc instance

---

# Source: Gemini (Google Search AI mode), 2026-11-21, unverified

## Prompts

1. Why doesn't debian 13 ship with "vkms" module?
2. I want podman rootless nested wayland containers

## Google-Search-AI mode response

You do not need vkms for rootless nested Wayland containers in Podman. Instead, run a lightweight host compositor in headless mode (which uses software rendering or existing GPU nodes) to generate a Wayland socket, and bind-mount that socket directly into your rootless Podman container.

### How It Works Without vkms

• No kernel modules or root privileges required: Headless Wayland compositors (labwc, sway, weston, cage) create a virtual output in user space without needing /dev/dri/card* from vkms.

• Zero host display needed: This works cleanly over SSH on a headless server (hwd4).

• Full isolation: Each container only sees the specific Wayland socket you mount into it, keeping sessions isolated from each other and the host.

### Step-by-Step Setup on Debian 13

1. Start a headless Wayland compositor on the host (as your regular user)

	Install a lightweight wlroots compositor like labwc or sway (or weston).

	Launch it in headless mode so it creates a dedicated Wayland socket in $XDG_RUNTIME_DIR (e.g., /run/user/1000/wayland-1):

	```WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 labwc &```

	(Verify the new socket appeared with ```ls -l $XDG_RUNTIME_DIR/wayland-*```.)

2. Run the rootless Podman container with that socket

	Pass the host's Wayland socket into the container and set WAYLAND_DISPLAY and XDG_RUNTIME_DIR:

``` bash
podman run --rm -it \
  --security-opt label=disable \
  -e XDG_RUNTIME_DIR=/tmp \
  -e WAYLAND_DISPLAY=wayland-1 \
  -v "$XDG_RUNTIME_DIR/wayland-1:/tmp/wayland-1" \
  debian:13 \
  bash
```

	(If you also want hardware-accelerated OpenGL/Vulkan inside the container via an existing physical GPU,
add --device /dev/dri/renderD128—note that /dev/dri/renderD* is already present if you have an Intel/AMD GPU, independent of vkms.)

3. Run a nested compositor or GUI app inside the container

	Inside the container, any Wayland application—or even a full nested compositor (e.g., weston, sway, gamescope)—will render onto the host's headless Wayland output:

```bash
apt update && apt install -y weston foot
foot
```


### When Would You Actually Need vkms?

You only need vkms if you are trying to run a DRM/KMS-only compositor inside a privileged/device-mapped container (such as running kmscon, cage, or sway directly against /dev/dri/card0 inside the container without a host compositor).
For standard rootless nested Wayland, a host headless compositor is cleaner, faster, and survives kernel updates without rebuilding modules.

If you'd like a tailored podman run or compose snippet, tell me:

• Which compositor or desktop environment you want to run inside the container

• Whether you need remote viewing (e.g., VNC/RDP via wayvnc) or GPU acceleration (/dev/dri/renderD128)
