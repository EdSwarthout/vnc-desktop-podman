ARG BASE=docker.io/library/ubuntu:26.04

# Stages, each runnable with d_run (d_target in env.rc picks one; the image is tagged
# u2604cc:<stage>):
#   base   - Ubuntu + network/debug tools + nested rootless podman; headless
#   vnc    - base + TigerVNC/noVNC, session is a bare xterm
#   chrome - vnc + Google Chrome (via the --no-sandbox wrapper)
#   xfce   - chrome + XFCE desktop
#   lxqt   - chrome + LXQt desktop
#   gnome  - chrome + GNOME Flashback desktop
# Each stage with a display installs /usr/local/bin/vnc-session, which the home's
# ~/.config/tigervnc/xstartup runs, so the session follows the image, not the home.

# ---------------------------------------------------------------------------------------
# Stage "base": minimal image with nested rootless podman, network and debug tools
FROM ${BASE} AS base

# The container user. d_build passes d_user and the builder's UID, so that with
# PODMAN_USERNS=keep-id it is the host user and owns the home volume.
ARG USERID=ed
ARG USER_UID=1001

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    USERID=${USERID}

# Keep downloaded .debs: d_build/d_run mount the shared (NFS) $d_aptcache on
# /var/cache/apt/archives. Ubuntu's docker-clean deletes .debs after every install, so
# drop it, but keep its other job: no pkgcache.bin/srcpkgcache.bin (~50 MB each, rebuilt
# from the lists anyway). Each apt RUN ends with
# `mountpoint -q /var/cache/apt/archives || apt-get clean`, so a plain `podman build`
# without the mount doesn't leave .debs in the image layers either.
RUN rm /etc/apt/apt.conf.d/docker-clean \
    && printf 'Dir::Cache::pkgcache "";\nDir::Cache::srcpkgcache "";\n' \
        > /etc/apt/apt.conf.d/docker-no-pkgcache

# Basics, network/debug and development tools, and nested rootless podman. The user
# has no root in the container (below), so what's needed at runtime has to be here.
# keep list sorted
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    bc \
    bind9-dnsutils \
    build-essential \
    bzip2 \
    ca-certificates \
    catatonit \
    curl \
    emacs-nox \
    file \
    fuse-overlayfs \
    gh \
    git \
    gnupg \
    iproute2 \
    iputils-ping \
    jq \
    less \
    libcap2-bin \
    lsof \
    nano \
    netcat-openbsd \
    nodejs \
    npm \
    openssh-client \
    passt \
    patch \
    podman \
    procps \
    python3-pip \
    python3-venv \
    ripgrep \
    rsync \
    shellcheck \
    strace \
    sudo \
    tmux \
    tree \
    uidmap \
    unzip \
    wget \
    xz-utils \
    zip \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

# Non-root user with a fixed UID; a user the base image ships with that UID (Ubuntu's
# "ubuntu" is 1000) makes way. No general root: the only thing it may sudo is the
# boot-time nested-subids (root-owned, and "" = without arguments), which start.sh
# runs. Add packages here and rebuild, or use `podman exec -u root` from outside.
RUN old=$(getent passwd "${USER_UID}" | cut -d: -f1) \
    && { [ -z "$old" ] || userdel -r "$old"; } \
    && useradd -m -s /bin/bash -u "${USER_UID}" ${USERID} \
    && echo "${USERID} ALL=(root) NOPASSWD: /usr/local/sbin/nested-subids \"\"" > /etc/sudoers.d/${USERID} \
    && chmod 440 /etc/sudoers.d/${USERID} \
    && visudo -cf /etc/sudoers.d/${USERID}

# Subordinate IDs must fit inside the 65536 UIDs the outer (rootless) container has;
# useradd's default ed:165536:65536 is outside it. Use 1 to UID-1 and UID+1 to 65535
# (skip the user's own; for ed, 1001: 1-1000 and 1002-65535): inner containers get root->ed plus 65534 subids. subgid also gets
# group 0 (ed:0:1), so root in a nested build can use the shared apt cache (see
# nested-subids). These are defaults: at every boot start.sh runs nested-subids, which
# rewrites them from the container's actual ID map (needed one level deeper, e.g.
# ccN_M) and re-applies the file caps below.
RUN printf '%s:1:%d\n%s:%d:%d\n' ${USERID} $((USER_UID - 1)) ${USERID} $((USER_UID + 1)) $((65535 - USER_UID)) > /etc/subuid \
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

# Fonts for web pages: metric-compatible Latin, CJK (else Chinese/Japanese/Korean text
# shows as empty boxes), emoji
# keep list sorted
RUN apt-get update && apt-get install -y --no-install-recommends \
    fonts-liberation \
    fonts-noto-cjk \
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
# Wrapper in /usr/local/bin shadows /usr/bin on PATH; menu entries are pointed at it too
# (the build fails if a new Chrome's .desktop files no longer have the expected Exec=),
# and it outranks Chrome's own alternatives (priority 200), because XFCE's default
# WebBrowser (exo-open --launch WebBrowser) is sensible-browser -> x-www-browser.
RUN printf '#!/bin/sh\nexec /usr/bin/google-chrome-stable --no-sandbox --no-first-run --no-default-browser-check "$@"\n' \
        > /usr/local/bin/google-chrome-stable \
    && chmod +x /usr/local/bin/google-chrome-stable \
    && ln -s google-chrome-stable /usr/local/bin/google-chrome \
    && for alt in gnome-www-browser google-chrome x-www-browser; do \
           update-alternatives --install /usr/bin/$alt $alt /usr/local/bin/google-chrome-stable 300; \
       done \
    && for f in google-chrome com.google.Chrome; do \
           sed -i 's|^Exec=/usr/bin/google-chrome-stable|Exec=/usr/local/bin/google-chrome-stable|' \
               /usr/share/applications/$f.desktop \
           && grep -q '^Exec=/usr/local/bin/google-chrome-stable' /usr/share/applications/$f.desktop \
           || { echo "$f.desktop: Exec= not pointed at the wrapper" >&2; exit 1; }; \
       done

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

# ---------------------------------------------------------------------------------------
# Stage "gnome": chrome + GNOME Flashback desktop (gnome-panel, metacity, nautilus)
FROM chrome AS gnome
USER root

# GNOME Flashback, GNOME's X11 session, not GNOME Shell: Ubuntu 26.04's GNOME Shell (50)
# is Wayland-only and needs logind, so it can't be a session on the VNC X server.
# gnome-session-flashback: the panel layout and Flashback's gsettings defaults (and
# gnome-flashback, gnome-panel, metacity, nautilus as dependencies).
# gnome-screenshot: tests/screenshot.sh
# keep list sorted
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnome-screenshot \
    gnome-session-flashback \
    gnome-terminal \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

# gnome-session needs systemd to start a session, so start Flashback's parts directly:
# the window manager, gnome-flashback (desktop background and icons, shortcuts,
# notifications) and the panel; the session lasts as long as the panel. The variables
# select Flashback's gsettings defaults and its applications menu.
# The panel's "Log Out" needs gnome-session, so it does nothing here: the menu's
# "Log Out (stop the container)" entry ends the session by closing the panel instead.
RUN printf '%s\n' '#!/bin/sh' \
        'export XDG_CURRENT_DESKTOP=GNOME-Flashback:GNOME XDG_MENU_PREFIX=gnome-flashback- XDG_SESSION_TYPE=x11' \
        'metacity &' \
        'gnome-flashback &' \
        'exec gnome-panel' \
        > /usr/local/bin/vnc-session \
    && printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Log Out (stop the container)' \
        'Exec=pkill -x gnome-panel' 'Icon=system-log-out' 'Categories=System;' \
        > /usr/share/applications/vnc-logout.desktop

# Panel layout: Ubuntu's default ("ubuntu") has an indicator applet that isn't
# installed, which leaves the top panel without clock or user menu; use GNOME
# Flashback's own layout. Only read when a home's panel is first set up.
RUN printf '%s\n' '[org.gnome.gnome-panel.general:GNOME-Flashback]' "default-layout='gnome-flashback'" \
        > /usr/share/glib-2.0/schemas/99_vnc-desktop.gschema.override \
    && glib-compile-schemas /usr/share/glib-2.0/schemas

USER ${USERID}
