#!/bin/sh
# Shared post-install setup for OpenCode Desktop (Ubuntu .deb and Fedora .rpm).
set -e

# Electron's sandbox needs user namespaces or a setuid chrome-sandbox, neither of which
# works in a rootless container: a wrapper in /usr/local/bin (ahead of the package's
# /usr/bin/ai.opencode on PATH) adds --no-sandbox, and the menu entries are pointed at it
# (the build fails if a new package's .desktop files no longer have the expected Exec=).
# --password-store=basic: Electron's safeStorage keeps secrets (provider logins) in a
# file instead of a keyring: the user has no password to unlock a keyring with, and
# LXQt has no keyring daemon.
printf '#!/bin/sh\nexec /opt/OpenCode/ai.opencode --no-sandbox --password-store=basic "$@"\n' \
    > /usr/local/bin/ai.opencode
chmod +x /usr/local/bin/ai.opencode
for f in ai.opencode.desktop opencode-desktop; do
    sed -i 's|^Exec=/opt/OpenCode/ai.opencode|Exec=/usr/local/bin/ai.opencode|' \
        "/usr/share/applications/$f.desktop"
    grep -q '^Exec=/usr/local/bin/ai.opencode' "/usr/share/applications/$f.desktop" \
        || { echo "$f.desktop: Exec= not pointed at the wrapper" >&2; exit 1; }
done

# The terminal UI: `opencode` is the desktop app's bundled CLI (one copy in the image).
# install_opencode (from the browser stage, run as the user like install_claude)
# installs opencode's own build in ~/.opencode/bin, which wins on PATH from the next
# shell on.
ln -s /opt/OpenCode/resources/opencode-cli /usr/local/bin/opencode
opencode --version
