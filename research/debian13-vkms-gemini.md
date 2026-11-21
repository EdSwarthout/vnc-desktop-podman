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

	> WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 labwc &

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
