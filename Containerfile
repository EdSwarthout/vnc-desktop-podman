ARG BASE=docker.io/library/ubuntu:26.04

# Stages, each runnable with d_run (d_target in env.rc picks one; the image is tagged
# u2604cc:<stage>):
#   base   - Ubuntu + network/debug tools + nested rootless podman; headless
#   vnc    - base + TigerVNC/noVNC, session is a bare xterm
#   chrome - vnc + Google Chrome (via the --no-sandbox wrapper)
#   xfce   - chrome + XFCE desktop
#   lxqt   - chrome + LXQt desktop
#   gnome  - chrome + GNOME Flashback desktop + claude-desktop
#   kde    - chrome + KDE Plasma desktop
#   mate   - chrome + MATE desktop
#   cinnamon - chrome + Cinnamon desktop
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
    iperf3 \
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
    seahorse \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

# gnome-session needs systemd to start a session, so start Flashback's parts directly:
# the window manager, gnome-flashback (desktop background and icons, shortcuts,
# notifications) and the panel; the session lasts as long as the panel. The variables
# select Flashback's gsettings defaults and its applications menu.
# The panel's "Log Out" needs gnome-session, so it does nothing here: the menu's
# "Log Out (stop the container)" entry ends the session by closing the panel instead.
# Keyring: claude-desktop stores its secrets in the default keyring (gnome-keyring,
# D-Bus activated). A new home has none, so gnome-keyring would ask for a password to
# create one, and claude-desktop hangs after that dialog. So the session gives a home
# without a default keyring a passwordless one (a plain-text keyring file): it unlocks
# without a prompt, and nothing asks for a password the user doesn't have. Secrets in it
# are not encrypted: they're protected only by the home's file permissions.
RUN printf '%s\n' '#!/bin/sh' \
        'export XDG_CURRENT_DESKTOP=GNOME-Flashback:GNOME XDG_MENU_PREFIX=gnome-flashback- XDG_SESSION_TYPE=x11' \
        'd=$HOME/.local/share/keyrings' \
        'if [ ! -e "$d/default" ]; then (' \
        '    umask 077; mkdir -p "$d"' \
        '    [ -e "$d/Default_keyring.keyring" ] || printf "%s\n" "[keyring]" "display-name=Default keyring" \' \
        '        "ctime=0" "mtime=0" "lock-on-idle=false" "lock-after=false" > "$d/Default_keyring.keyring"' \
        '    printf Default_keyring > "$d/default"' \
        ') fi' \
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
# No screen locking: the user has no password, so a locked screen couldn't be unlocked,
# and by default it locks after 5 idle minutes. gnome-flashback's screensaver component
# is the locker, so it's switched off.
RUN printf '%s\n' '[org.gnome.gnome-panel.general:GNOME-Flashback]' "default-layout='gnome-flashback'" \
        '[org.gnome.gnome-flashback]' 'screensaver=false' \
        '[org.gnome.desktop.lockdown]' 'disable-lock-screen=true' \
        > /usr/share/glib-2.0/schemas/99_vnc-desktop.gschema.override \
    && glib-compile-schemas --strict /usr/share/glib-2.0/schemas

# Claude desktop app, from Anthropic's apt repository. The key and the sources file go
# where the package's own postinst puts them, so it doesn't add a second entry.
# gnome-keyring: where claude-desktop stores its secrets (see vnc-session above)
RUN curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc \
        https://downloads.claude.ai/keys/claude-code.asc \
    && echo 'deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main' \
        > /etc/apt/sources.list.d/claude-desktop.list \
    && apt-get update && apt-get install -y claude-desktop gnome-keyring \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

USER ${USERID}

# ---------------------------------------------------------------------------------------
# Stage "kde": chrome + KDE Plasma desktop (X11 session)
FROM chrome AS kde
USER root

# plasma-session-x11 + kwin-x11: Plasma's X11 session (the default one is Wayland).
# kde-spectacle: tests/screenshot.sh
# keep list sorted
RUN apt-get update && apt-get install -y --no-install-recommends \
    dolphin \
    kde-spectacle \
    konsole \
    kwin-x11 \
    plasma-desktop \
    plasma-session-x11 \
    systemsettings \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

# SHELL: nothing sets it in the container (no login), and Konsole warns without it.
# No screen locking, automatic or by hand (kiosk restriction): the user has no password,
# so a locked screen couldn't be unlocked.
# The update script (run once per home by plasmashell) sets the task bar's pinned
# launchers: the default ones include Discover, which isn't installed (a blank icon).
RUN printf '%s\n' '#!/bin/sh' 'export SHELL="${SHELL:-/bin/bash}"' 'exec startplasma-x11' \
        > /usr/local/bin/vnc-session \
    && printf '%s\n' '[Daemon]' 'Autolock=false' 'LockOnResume=false' > /etc/xdg/kscreenlockerrc \
    && printf '%s\n' '[KDE Action Restrictions][$i]' 'action/lock_screen=false' > /etc/xdg/kdeglobals \
    && d=/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates && test -d $d \
    && printf '%s\n' \
        'for (const panel of panels()) {' \
        '    for (const id of panel.widgetIds) {' \
        '        const w = panel.widgetById(id);' \
        '        if (w.type !== "org.kde.plasma.icontasks") continue;' \
        '        w.currentConfigGroup = ["General"];' \
        '        w.writeConfig("launchers", ["applications:systemsettings.desktop", "preferred://filemanager", "preferred://browser", "applications:org.kde.konsole.desktop"]);' \
        '    }' \
        '}' \
        > $d/vnc-desktop-launchers.js

USER ${USERID}

# ---------------------------------------------------------------------------------------
# Stage "mate": chrome + MATE desktop
FROM chrome AS mate
USER root

# scrot: tests/screenshot.sh (MATE's own mate-screenshot can only save through a dialog)
# keep list sorted
RUN apt-get update && apt-get install -y --no-install-recommends \
    mate-desktop-environment-core \
    mate-terminal \
    scrot \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

# Panel layout: Ubuntu's default ("familiar") uses applets that aren't installed (they
# show as "Error" boxes, and the top panel stays empty); use MATE's own default. Only
# read when a home's panel is first set up.
RUN printf '#!/bin/sh\nexec mate-session\n' > /usr/local/bin/vnc-session \
    && printf '%s\n' '[org.mate.panel]' "default-layout='default'" \
        > /usr/share/glib-2.0/schemas/99_vnc-desktop.gschema.override \
    && glib-compile-schemas /usr/share/glib-2.0/schemas

USER ${USERID}

# ---------------------------------------------------------------------------------------
# Stage "cinnamon": chrome + Cinnamon desktop
FROM chrome AS cinnamon
USER root

# scrot: tests/screenshot.sh
# keep list sorted
RUN apt-get update && apt-get install -y --no-install-recommends \
    cinnamon-core \
    gnome-terminal \
    scrot \
    && { mountpoint -q /var/cache/apt/archives || apt-get clean; } \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin

# cinnamon2d: Cinnamon's software-rendering session (there's no GPU behind the VNC X
# server).
# No screen locking: the user has no password, so a locked screen couldn't be unlocked.
# The settings turn off idle activation and hide the menu's Lock Screen, but an explicit
# lock request still locks, so the screensaver isn't run at all: it's taken out of the
# session's components and its D-Bus activation file is removed (the greps fail the
# build if a new Cinnamon moves these).
RUN printf '#!/bin/sh\nexec cinnamon-session-cinnamon2d\n' > /usr/local/bin/vnc-session \
    && f=/usr/share/cinnamon-session/sessions/cinnamon2d.session \
    && grep -q '^RequiredComponents=.*;org.cinnamon.ScreenSaver;' $f \
    && sed -i '/^RequiredComponents=/s/;org.cinnamon.ScreenSaver;/;/' $f \
    && grep -q '^Exec=/usr/bin/cinnamon-screensaver$' /usr/share/dbus-1/services/org.cinnamon.ScreenSaver.service \
    && rm /usr/share/dbus-1/services/org.cinnamon.ScreenSaver.service \
    && printf '%s\n' \
        '[org.cinnamon.desktop.lockdown]' 'disable-lock-screen=true' \
        '[org.cinnamon.desktop.screensaver]' 'lock-enabled=false' \
        '[org.cinnamon.desktop.session]' 'idle-delay=uint32 0' \
        > /usr/share/glib-2.0/schemas/99_vnc-desktop.gschema.override \
    && glib-compile-schemas --strict /usr/share/glib-2.0/schemas

USER ${USERID}
