ARG BASE=docker.io/library/ubuntu:26.04

# Stages, each runnable with d_run (d_target in env.rc picks one; the image is tagged
# u2604cc:<stage>):
#   base   - Ubuntu + network/debug tools + nested rootless podman; headless
#   vnc    - base + TigerVNC/noVNC, session is a bare xterm
#   chrome - vnc + Google Chrome (via the --no-sandbox wrapper)
#   xfce   - chrome + XFCE desktop
#   lxqt   - chrome + LXQt desktop
# Each stage with a display installs /usr/local/bin/vnc-session, which the home's
# ~/.config/tigervnc/xstartup runs, so the session follows the image, not the home.

# ---------------------------------------------------------------------------------------
# Stage "base": minimal image with nested rootless podman, network and debug tools
FROM ${BASE} AS base

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    USERID=ed

# Keep downloaded .debs: d_build/d_run mount the shared (NFS) $d_aptcache on
# /var/cache/apt/archives. Ubuntu's docker-clean deletes .debs after every install, so
# drop it, but keep its other job: no pkgcache.bin/srcpkgcache.bin (~50 MB each, rebuilt
# from the lists anyway). Each apt RUN ends with
# `mountpoint -q /var/cache/apt/archives || apt-get clean`, so a plain `podman build`
# without the mount doesn't leave .debs in the image layers either.
RUN rm /etc/apt/apt.conf.d/docker-clean \
    && printf 'Dir::Cache::pkgcache "";\nDir::Cache::srcpkgcache "";\n' \
        > /etc/apt/apt.conf.d/docker-no-pkgcache

# Basics, network/debug tools, and nested rootless podman
# keep list sorted
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    ca-certificates \
    catatonit \
    curl \
    emacs-nox \
    fuse-overlayfs \
    git \
    gnupg \
    iproute2 \
    iputils-ping \
    libcap2-bin \
    nano \
    nodejs \
    npm \
    passt \
    podman \
    procps \
    ripgrep \
    strace \
    sudo \
    uidmap \
    wget \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

# Non-root user (ubuntu base images may already ship an "ubuntu" user, so use our own name)
RUN useradd -m -s /bin/bash -G sudo ${USERID} \
    && echo "${USERID} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERID}

# Subordinate IDs must fit inside the 65536 UIDs the outer (rootless) container has;
# useradd's default ed:165536:65536 is outside it. Use 1-1000 and 1002-65535 (skip
# ed's own 1001): inner containers get root->ed plus 65534 subids. subgid also gets
# group 0 (ed:0:1), so root in a nested build can use the shared apt cache (see
# nested-subids). These are defaults: at every boot start.sh runs nested-subids, which
# rewrites them from the container's actual ID map (needed one level deeper, e.g.
# ccN_M) and re-applies the file caps below.
RUN printf '%s:1:1000\n%s:1002:64534\n' ${USERID} ${USERID} > /etc/subuid \
    && { cat /etc/subuid; printf '%s:0:1\n' ${USERID}; } > /etc/subgid

# setuid-root newuidmap runs with euid 0, which is not the owner of the new user
# namespace, so writing uid_map needs CAP_SYS_ADMIN, which the outer container lacks
# (EPERM). With file caps instead, euid stays ed (the owner); it only adds SETUID/SETGID.
RUN chmod u-s /usr/bin/newuidmap /usr/bin/newgidmap \
    && setcap cap_setuid=ep /usr/bin/newuidmap \
    && setcap cap_setgid=ep /usr/bin/newgidmap

# No systemd/logind in the container: no cgroup delegation, no journald.
# utsns = "host": the outer seccomp profile blocks sethostname without CAP_SYS_ADMIN,
# so nested containers share the instance's hostname instead of setting their own.
RUN mkdir -p /etc/containers/containers.conf.d && printf '%s\n' \
        '[containers]' \
        'cgroups = "disabled"' \
        'utsns = "host"' \
        '' \
        '[engine]' \
        'cgroup_manager = "cgroupfs"' \
        'events_logger = "file"' \
        > /etc/containers/containers.conf.d/nested.conf

COPY --chmod=755 nested-subids /usr/local/sbin/nested-subids

# Claude Code: run install_claude as the user at runtime. The native installer puts it in
# ~/.local/bin (home volume), so it persists and self-updates.
RUN printf '#!/bin/bash\nset -ex\ncurl -fsSL https://claude.ai/install.sh | bash\n' \
    > /usr/local/bin/install_claude \
    && chmod +x /usr/local/bin/install_claude

# start.sh: first-boot home setup and nested-subids; then the VNC session if the stage
# has one, otherwise it just waits (use `podman exec -it <name> bash`).
COPY --chmod=755 start.sh /usr/local/bin/start.sh

USER ${USERID}
WORKDIR /home/${USERID}
CMD ["/usr/local/bin/start.sh"]

# ---------------------------------------------------------------------------------------
# Stage "vnc": TigerVNC server/viewer and noVNC, no desktop: the session is an xterm
FROM base AS vnc
USER root

ENV DISPLAY=:1 \
    VNC_RESOLUTION=1440x900

# dbus-x11: xstartup runs the session under dbus-launch (desktops and Chrome use the bus)
# keep list sorted
RUN apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 \
    novnc \
    tigervnc-standalone-server \
    tigervnc-tools \
    tigervnc-viewer \
    websockify \
    xterm \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

# The session: closing it (exit the xterm, or log out of a desktop) stops the container.
RUN printf '#!/bin/sh\nexec xterm\n' > /usr/local/bin/vnc-session \
    && chmod +x /usr/local/bin/vnc-session

USER ${USERID}
EXPOSE 5901 6080

# ---------------------------------------------------------------------------------------
# Stage "chrome": vnc + Google Chrome
FROM vnc AS chrome
USER root

# keep list sorted
RUN apt-get update && apt-get install -y --no-install-recommends \
    fonts-liberation \
    fonts-noto-color-emoji \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

# Google Chrome (amd64 only). The .deb's postinst adds Google's apt repo + key itself.
RUN curl -fsSLo /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get update && apt-get install -y /tmp/chrome.deb \
    && rm -f /tmp/chrome.deb \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

# Chrome needs these flags in a container (no user-namespace sandbox).
# Wrapper in /usr/local/bin shadows /usr/bin on PATH; menu entries are pointed at it too,
# and it outranks Chrome's own alternatives (priority 200), because XFCE's default
# WebBrowser (exo-open --launch WebBrowser) is sensible-browser -> x-www-browser.
RUN printf '#!/bin/sh\nexec /usr/bin/google-chrome-stable --no-sandbox --no-first-run --no-default-browser-check "$@"\n' \
        > /usr/local/bin/google-chrome-stable \
    && chmod +x /usr/local/bin/google-chrome-stable \
    && ln -s google-chrome-stable /usr/local/bin/google-chrome \
    && for alt in gnome-www-browser google-chrome x-www-browser; do \
           update-alternatives --install /usr/bin/$alt $alt /usr/local/bin/google-chrome-stable 300; \
       done \
    && sed -i 's|^Exec=/usr/bin/google-chrome-stable|Exec=/usr/local/bin/google-chrome-stable|' \
        /usr/share/applications/google-chrome.desktop /usr/share/applications/com.google.Chrome.desktop

USER ${USERID}

# ---------------------------------------------------------------------------------------
# Stage "xfce": chrome + XFCE desktop
FROM chrome AS xfce
USER root

# xfce4-screenshooter: tests/screenshot.sh uses it
# keep list sorted
RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-screenshooter \
    xfce4-terminal \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

RUN printf '#!/bin/sh\nexec startxfce4\n' > /usr/local/bin/vnc-session

USER ${USERID}

# ---------------------------------------------------------------------------------------
# Stage "lxqt": chrome + LXQt desktop
FROM chrome AS lxqt
USER root

# Not pulled in without recommends: breeze-icon-theme (LXQt's default icon theme; else
# the panel and desktop have no icons), libxcb-cursor0 (Qt 6's xcb platform plugin won't
# load without it, so no LXQt app starts), lxqt-menu-data (the application menu; the
# panel's menu button is missing without it), openbox (a window manager),
# qt6-svg-plugins (SVG icons, e.g. the menu button's start-here-lxqt).
# screengrab: tests/screenshot.sh
# keep list sorted
RUN apt-get update && apt-get install -y --no-install-recommends \
    breeze-icon-theme \
    libxcb-cursor0 \
    lxqt-core \
    lxqt-menu-data \
    openbox \
    qt6-svg-plugins \
    qterminal \
    screengrab \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

# Panel without the volume plugin: there's no sound device in the container, so it only
# shows a red X. /etc/xdg comes before /usr/share in LXQt's XDG_CONFIG_DIRS, and homes'
# panel.conf don't store the plugin list, so this applies to existing homes too. The
# grep fails the build if a new lxqt-panel changes the default list.
RUN printf '#!/bin/sh\nexec startlxqt\n' > /usr/local/bin/vnc-session \
    && grep -q '^plugins=.*,volume,' /usr/share/lxqt/panel.conf \
    && mkdir -p /etc/xdg/lxqt \
    && sed '/^plugins=/s/,volume,/,/' /usr/share/lxqt/panel.conf > /etc/xdg/lxqt/panel.conf

USER ${USERID}
