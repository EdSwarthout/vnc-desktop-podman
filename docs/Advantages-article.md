# A full Linux desktop for your AI agent, in a rootless container

I wanted a place where a coding agent can do anything it needs — browse, build, run
containers, click around a GUI — without being able to touch my real machine. So I
built vnc-desktop-podman: Linux desktops (Ubuntu 26.04, Debian 13, Fedora 45, and Arch
Linux) in rootless podman containers, reachable over VNC or a browser tab.

Here is what I like about it.

## 1. Nothing runs as root, anywhere

The container is rootless podman on the host, and the user inside has no sudo.
Everything the desktop needs is baked into the image. If the agent goes wrong, the
blast radius is one home directory.

## 2. Four distros, seven desktops, and ready-to-use agent desktops

Each distro builds `base → vnc → browser`, and modular per-desktop Containerfiles layer
on top: XFCE, LXQt, GNOME Flashback, KDE Plasma, MATE, and Cinnamon on Ubuntu; GNOME
Shell on Debian; XFCE and LXQt on Fedora; Openbox on Arch Linux — plus agent desktops
(OpenCode, Google Antigravity, and Claude Desktop) and a Chrome DevTools automation
image. Pick any combination with `d_distro` and `d_target`. Each instance gets its own
name, ports, and home directory (`vnc-desktop-ubuntu-lxqt-2604-6901`), so trying another
desktop or distro leaves your setup alone.

## 3. Your home survives rebuilds

Each instance keeps its home on the host as a volume. Rebuild the image as often as
you like: browser profile, settings, and coding-agent CLIs stay put.

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
the container. Per-distro package caches (shareable over NFS) keep rebuilds fast.

## What it is not

VNC traffic is unencrypted and the ports listen on all interfaces by default, so this
is for a trusted LAN or behind an SSH tunnel (`d_bind=127.0.0.1` in `.env`), not the
open internet.

Google Chrome (Chromium on Arch) and installers for coding-agent CLIs (Claude Code,
Antigravity, OpenCode, Grok, T3 Code) are included in every `browser` image; dedicated
agent desktops add OpenCode Desktop, the Google Antigravity App + Python SDK, and the
beta Claude desktop app.

Apache 2.0, on GitHub: <https://github.com/EdSwarthout/vnc-desktop-podman>
