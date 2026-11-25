# A full Linux desktop for your AI agent, in a rootless container

I wanted a place where a coding agent can do anything it needs — browse, build, run
containers, click around a GUI — without being able to touch my real machine. So I
built vnc-desktop-podman: an Ubuntu 26.04 desktop in a rootless podman container,
reachable over VNC or a browser tab.

Here is what I like about it.

## 1. Nothing runs as root, anywhere

The container is rootless podman on the host, and the user inside has no sudo.
Everything the desktop needs is baked into the image. If the agent goes wrong, the
blast radius is one home directory.

## 2. Six desktops from one Containerfile

XFCE, LXQt, GNOME Flashback, KDE Plasma, MATE and Cinnamon are all stages of the same
file, plus a headless stage and a bare-xterm one. Pick one with a single variable. Each
desktop gets its own instance and home, named after its image and port
(`vnc-desktop-ubuntu-lxqt-2604-6901`), so trying another desktop leaves your setup alone.

## 3. Your home survives rebuilds

Each instance keeps its home on the host as a volume. Rebuild the image as often as
you like: browser profile, settings and the Claude Code install stay put.

## 4. Containers inside the container

Every stage has its own nested rootless podman. The agent can build and run
containers without ever seeing the host's images — and it can build this very image
and start a desktop inside the desktop to test its own changes.

## 5. The agent can see what it built

A screenshot script works on every desktop, so an agent can start a nested instance,
take a picture and check the result itself. That is how most of the desktop stages
were debugged.

## 6. Easy to reach, easy to run many

Open it in a browser tab through noVNC, or use any VNC client. Instances are
numbered, each with its own ports and home, so running several side by side is one
command each.

## 7. Small things done properly

The VNC password never sits in the container's environment. Screen locking is off
everywhere, because a user with no password could never unlock it. Logging out stops
the container. A shared apt cache keeps rebuilds fast.

## What it is not

VNC traffic is unencrypted and the ports listen on all interfaces, so this is for a
trusted LAN or behind an SSH tunnel, not the open internet.

Chrome and Claude Code are included; the GNOME stage also has the Claude desktop app,
which is still in beta.

Apache 2.0, on GitHub: <https://github.com/EdSwarthout/vnc-desktop-podman>
