#!/bin/bash
# Unit tests for env.rc and chrome/env.rc with a stubbed podman (no container runtime or
# network needed). Runs fast on both host and CI.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1: $2" >&2; fails=$((fails + 1)); }

run_env() {
    # Run bash snippet with env.rc sourced, clean env, and stubbed podman.
    local script=$1
    # shellcheck disable=SC2016  # $HOME and $* expand in the inner bash -c
    env -i PATH="$PATH" HOME="$tmp/home" USER=tester bash -c '
        set -euo pipefail
        mkdir -p "$HOME"
        podman() {
            if [ "${1:-}" = image ] && [ "${2:-}" = inspect ]; then
                [ -n "${STUB_INSPECT:-}" ] && echo "$STUB_INSPECT"
                return 0
            fi
            echo "[podman $*]"
            case ${1:-} in
                container) return 1 ;;   # container exists -> false by default
                ps) return 0 ;;
                pull) [ -z "${STUB_PULL_FAIL:-}" ] ;;
                # image exists: true only for the images listed in $STUB_IMAGES
                image) [ "${2:-}" != exists ] || [[ " ${STUB_IMAGES:-} " == *" ${3:-} "* ]] ;;
            esac
        }
        export -f podman
        '"$script"
}

# 1. d_0 pulls upstream base image even with default d_target=lxqt
out=$(run_env "source '$repo/env.rc'; d_0")
if grep -Fq '[podman pull docker.io/library/ubuntu:26.04]' <<< "$out"; then
    pass "d_0 pulls ubuntu upstream base with default d_target=lxqt"
else
    fail "d_0 default" "got: $out"
fi

out=$(run_env "source '$repo/env.rc'; d_distro=debian d_0")
if grep -Fq '[podman pull docker.io/library/debian:trixie]' <<< "$out"; then
    pass "d_0 pulls debian upstream base"
else
    fail "d_0 debian" "got: $out"
fi

out=$(run_env "source '$repo/env.rc'; d_distro=fedora d_0")
if grep -Fq '[podman pull registry.fedoraproject.org/fedora:45]' <<< "$out"; then
    pass "d_0 pulls fedora upstream base"
else
    fail "d_0 fedora" "got: $out"
fi

# 2. d_select naming & ports (host vs nested, agent desktops, short & long d_target)
out=$(run_env "container=; source '$repo/env.rc'; d_dir='$tmp/h'; d_select 1")
if [[ $out == "u26-lxqt-6901 $tmp/h/u26-lxqt-6901 ports 6901 6081" ]]; then
    pass "d_select host naming and ports"
else
    fail "d_select host" "got: $out"
fi

out=$(run_env "container=podman D_NAME=u26-gnome-agy-7201; source '$repo/env.rc'; d_target=gnome-cl d_select 1")
if [[ $out == "7201-u26-gnome-cl-7401 /home/tester/Containers/7201-u26-gnome-cl-7401 ports 7401 6581" ]]; then
    pass "d_select nested naming prefixes parent port and abbreviates target"
else
    fail "d_select nested port" "got: $out"
fi

out=$(run_env "container=podman D_NAME=7201-u26-gnome-cl-7401; source '$repo/env.rc'; d_select 2")
if [[ $out == "7201-7401-u26-lxqt-6902 /home/tester/Containers/7201-7401-u26-lxqt-6902 ports 6902 6082" ]]; then
    pass "d_select 2-level nested naming preserves ancestor port chain"
else
    fail "d_select 2-level nested" "got: $out"
fi

out=$(run_env "container=podman D_NAME=outer1; source '$repo/env.rc'; d_select 2")
if [[ $out == "outer1_u26-lxqt-6902 /home/tester/Containers/outer1_u26-lxqt-6902 ports 6902 6082" ]]; then
    pass "d_select nested fallback naming for non-port parent"
else
    fail "d_select nested" "got: $out"
fi

out_long=$(run_env "container=; source '$repo/env.rc'; d_dir='$tmp/h'; d_target=lxqt-opencode d_select 3")
out_short=$(run_env "container=; source '$repo/env.rc'; d_dir='$tmp/h'; d_target=lxqt-oc d_select 3")
if [[ $out_long == "u26-lxqt-oc-7153 $tmp/h/u26-lxqt-oc-7153 ports 7153 6333" ]] && [[ $out_short == "$out_long" ]]; then
    pass "d_select agent desktop naming matches for both long (lxqt-opencode) and short (lxqt-oc)"
else
    fail "d_select agent" "long=$out_long | short=$out_short"
fi

out=$(run_env "container=; source '$repo/env.rc'; d_dir='$tmp/h'; d_distro=fedora d_target=lxqt-agy d_select 7")
if [[ $out == "f45-lxqt-agy-7207 $tmp/h/f45-lxqt-agy-7207 ports 7207 6387" ]]; then
    pass "d_select fedora short distro + abbreviated agent"
else
    fail "d_select fedora agy" "got: $out"
fi

# 3. d_run: passwd.init, no VNC_PASSWORD in podman args, d_bind, no debug pasta by default
out=$(run_env "VNC_PASSWORD=secret container=; source '$repo/env.rc'; d_dir='$tmp/run1'; d_select 1; d_run")
if grep -Fq -- '--hostname u26-lxqt-6901' <<< "$out" \
   && grep -Fq -- '-p 6901:5901 -p 6081:6080' <<< "$out" \
   && ! grep -Fq 'secret' <<< "$out" \
   && ! grep -Fq 'pasta:' <<< "$out" \
   && [ -s "$tmp/run1/u26-lxqt-6901/.config/tigervnc/passwd.init" ] \
   && [ "$(stat -c '%a' "$tmp/run1/u26-lxqt-6901/.config/tigervnc/passwd.init")" = 600 ]; then
    pass "d_run host defaults, passwd.init mode 600, no leaked password or pasta debug opts"
else
    fail "d_run host" "got: $out"
fi

out=$(run_env "VNC_PASSWORD=secret container=; source '$repo/env.rc'; d_dir='$tmp/run2'; d_bind=127.0.0.1; d_select 1; d_run")
if grep -Fq -- '-p 127.0.0.1:6901:5901 -p 127.0.0.1:6081:6080' <<< "$out"; then
    pass "d_run respects d_bind=127.0.0.1"
else
    fail "d_run d_bind" "got: $out"
fi

out=$(run_env "VNC_PASSWORD=secret container=; source '$repo/env.rc'; d_dir='$tmp/run3'; d_bind=127.0.0.1:; d_select 1; d_run")
if grep -Fq -- '-p 127.0.0.1:6901:5901 -p 127.0.0.1:6081:6080' <<< "$out"; then
    pass "d_run respects d_bind=127.0.0.1: (trailing colon)"
else
    fail "d_run d_bind colon" "got: $out"
fi

out=$(run_env "container=podman D_NAME=outer1; source '$repo/env.rc'; d_dir='$tmp/run4'; d_target=base; d_select 1; d_run")
if ! grep -Fq -- '--hostname' <<< "$out" && grep -Fq -- 'outer1_u26-base-6901' <<< "$out"; then
    pass "d_run nested base omits --hostname and needs no VNC_PASSWORD"
else
    fail "d_run nested base" "got: $out"
fi

# 4. d_build & d_build_fresh: shared deb/Containerfile, USER_GID, --pull=newer only on root stage
mkdir -p "$tmp/cache/apt-cache-ubuntu/archives" "$tmp/cache/apt-cache-debian/archives"
out=$(run_env "container=; source '$repo/env.rc'; d_dir='$tmp/cache'; d_target=lxqt-oc d_build_fresh")
browser_line=$(grep -F '[podman build ' <<< "$out" | grep -F -- '-t vnc-desktop-ubuntu:browser-2604' || true)
lxqt_line=$(grep -F '[podman build ' <<< "$out" | grep -F -- '-t vnc-desktop-ubuntu:lxqt-2604' || true)
opencode_line=$(grep -F '[podman build ' <<< "$out" | grep -F -- '-t vnc-desktop-ubuntu:lxqt-opencode-2604' || true)
if grep -Fq -- '--pull=newer --no-cache' <<< "$browser_line" \
   && grep -Fq -- 'container/deb/Containerfile' <<< "$browser_line" \
   && grep -Fq -- '--build-arg DISTRO=ubuntu --build-arg USER_FILES_GLOB=ubunt[u]' <<< "$browser_line" \
   && grep -Fq -- '--build-arg USER_GID=' <<< "$browser_line" \
   && grep -Fq -- '--no-cache' <<< "$lxqt_line" \
   && ! grep -Fq -- '--pull' <<< "$lxqt_line" \
   && grep -Fq -- '--no-cache' <<< "$opencode_line" \
   && grep -Fq -- 'OpenCode Desktop and CLI' <<< "$opencode_line" \
   && ! grep -Fq -- '--pull' <<< "$opencode_line"; then
    pass "d_build_fresh accepts abbreviated d_target (lxqt-oc), builds canonical tag + OCI desc, passes --pull=newer only to root stage"
else
    fail "d_build_fresh" "browser=$browser_line | lxqt=$lxqt_line | opencode=$opencode_line"
fi

out=$(run_env "container=; source '$repo/env.rc'; d_dir='$tmp/cache'; d_distro=debian d_target=gnome d_build")
if grep -Fq -- '--build-arg DISTRO=debian --build-arg USER_FILES_GLOB=debia[n]' <<< "$out" \
   && grep -Fq -- '-t vnc-desktop-debian:gnome-13' <<< "$out"; then
    pass "d_build debian uses deb/Containerfile with DISTRO=debian"
else
    fail "d_build debian" "got: $out"
fi

if run_env "container=; source '$repo/env.rc'; d_distro=debian d_target=kde d_build" >/dev/null 2>&1; then
    fail "invalid target" "expected debian+kde to fail"
else
    pass "invalid distro+target rejected"
fi

# 5. d_screenshots safety: refuses existing target home or used port without deleting it
mkdir -p "$tmp/shot/u26-xfce-6905"
touch "$tmp/shot/u26-xfce-6905/sentinel"
if run_env "container=; source '$repo/env.rc'; d_dir='$tmp/shot'; d_target=lxqt; d_screenshots 5 xfce" >/dev/null 2>&1; then
    fail "d_screenshots collision" "expected d_screenshots to refuse existing xfce home"
elif [ -f "$tmp/shot/u26-xfce-6905/sentinel" ]; then
    pass "d_screenshots refuses existing target home and preserves it"
else
    fail "d_screenshots collision" "sentinel file was deleted!"
fi

if run_env "container=; source '$repo/env.rc'; d_dir='$tmp/shot'; d_target=lxqt; d_screenshots 5 gnome" >/dev/null 2>&1; then
    fail "d_screenshots port collision" "expected d_screenshots to refuse used port 6905"
elif [ -f "$tmp/shot/u26-xfce-6905/sentinel" ]; then
    pass "d_screenshots refuses port collision from another target"
else
    fail "d_screenshots port collision" "sentinel file was deleted!"
fi

# 6. d_exec handles -- end-of-options
out=$(run_env "container=; source '$repo/env.rc'; d_select 1; d_exec -d -- -foo bar")
if grep -Fq -- '[podman exec -d u26-lxqt-6901 setpriv --inh-caps=-all --ambient-caps=-all -foo bar]' <<< "$out"; then
    pass "d_exec handles -- option terminator"
else
    fail "d_exec --" "got: $out"
fi

# 7. chrome/env.rc: set -u safety and shell-safe quoting in d_chrome_mcp
out=$(run_env "container=; source '$repo/env.rc'; d_select 1; d_devtools_opts=('--foo=a b'); d_chrome_mcp")
if grep -Fq -- '--foo=a\ b' <<< "$out" || grep -Fq -- "'--foo=a b'" <<< "$out"; then
    pass "d_chrome_mcp shell-quotes d_devtools_opts"
else
    fail "d_chrome_mcp quoting" "got: $out"
fi

out=$(run_env "container=; source '$repo/env.rc'; d_select 1; d_chrome_mcp")
if grep -Fq -- 'claude mcp add chrome-u26-lxqt-6901' <<< "$out"; then
    pass "d_chrome_mcp safe under set -u with unset d_devtools_opts"
else
    fail "d_chrome_mcp set -u" "got: $out"
fi

# 8. arm64 (aarch64) excludes archlinux
out=$(env -i PATH="$PATH" HOME="$tmp/home" USER=tester bash -c "
    uname() { [ \"\${1:-}\" = -m ] && echo aarch64 || command uname \"\$@\"; }
    export -f uname
    source '$repo/env.rc'
    if d_distro=archlinux d_select 1 2>/dev/null; then echo BAD; else echo OK; fi
")
if [ "$out" = OK ]; then
    pass "aarch64 excludes archlinux"
else
    fail "aarch64 archlinux" "got: $out"
fi

# 9. d_commit commits selected container and clears commit-requested marker
mkdir -p "$tmp/commit/u26-lxqt-6901/.config/vnc-desktop"
printf '2026-11-26T00:00:00Z install htop\n' > "$tmp/commit/u26-lxqt-6901/.config/vnc-desktop/commit-requested"
out=$(run_env "container=; source '$repo/env.rc'; d_dir='$tmp/commit'; d_select 1; d_commit")
if grep -Fq -- '[podman commit --pause=false u26-lxqt-6901 vnc-desktop-ubuntu:lxqt-2604-6901]' <<< "$out" \
   && [ ! -e "$tmp/commit/u26-lxqt-6901/.config/vnc-desktop/commit-requested" ] \
   && grep -Fq 'vnc-desktop-ubuntu:lxqt-2604-6901 (2026-11-26T00:00:00Z install htop)' "$tmp/commit/u26-lxqt-6901/.config/vnc-desktop/commit-done"; then
    pass "d_commit commits to the instance tag, clears commit-requested, writes commit-done"
else
    fail "d_commit default" "got: $out"
fi

out=$(run_env "container=; source '$repo/env.rc'; d_dir='$tmp/commit'; d_select 1; d_commit :lxqt-snap")
if grep -Fq -- 'vnc-desktop-ubuntu:lxqt-snap]' <<< "$out"; then
    pass "d_commit supports :tag shorthand"
else
    fail "d_commit :tag" "got: $out"
fi

# d_run and d_run_cmd start the committed image when it exists, the built one otherwise
ci=vnc-desktop-ubuntu:lxqt-2604-6901
out=$(run_env "VNC_PASSWORD=x STUB_IMAGES='$ci' container=; source '$repo/env.rc'; d_dir='$tmp/commit2'; d_select 1; d_run; d_run_cmd true" 2>&1)
if [ "$(grep -c -- " $ci" <<< "$out")" -ge 2 ] && grep -Fq 'd_run: using committed image' <<< "$out"; then
    pass "d_run/d_run_cmd prefer the instance's committed image"
else
    fail "d_run committed image" "got: $out"
fi
out=$(run_env "VNC_PASSWORD=x STUB_IMAGES='$ci' container=; source '$repo/env.rc'; d_dir='$tmp/commit3'; d_select 1; d_use_commit=0 d_run" 2>&1)
if grep -q -- ' vnc-desktop-ubuntu:lxqt-2604$' <<< "$out" && ! grep -Fq -- "$ci" <<< "$out"; then
    pass "d_use_commit=0 starts the built image"
else
    fail "d_use_commit=0" "got: $out"
fi
out=$(run_env "STUB_IMAGES='$ci' container=; source '$repo/env.rc'; d_dir='$tmp/commit4'; d_select 1; d_uncommit; d_rm -f" 2>&1)
if grep -Fq -- "[podman untag $ci]" <<< "$out" && grep -Fq "removed u26-lxqt-6901 and image $ci" <<< "$out"; then
    pass "d_uncommit and d_rm remove the committed image"
else
    fail "d_uncommit/d_rm" "got: $out"
fi

# 10. container/vnc-pkg argument validation (dry-run mode)
if [ "$(VNC_PKG_DRY_RUN=1 bash "$repo/container/vnc-pkg" upgrade)" = "dry-run: upgrade " ] \
   && [ "$(VNC_PKG_DRY_RUN=1 bash "$repo/container/vnc-pkg" install htop gcc-c++ libc6:amd64)" = "dry-run: install htop gcc-c++ libc6:amd64" ] \
   && [ "$(VNC_PKG_DRY_RUN=1 bash "$repo/container/vnc-pkg" remove htop)" = "dry-run: remove htop" ]; then
    pass "vnc-pkg accepts valid upgrade/install/remove invocations"
else
    fail "vnc-pkg valid args" "unexpected dry-run output"
fi

bad_ok=1
for bad in \
    "upgrade extra" \
    "install" \
    "remove" \
    "install -oAPT::Update::Pre-Invoke::=id" \
    "install /tmp/evil.deb" \
    "install https://example.com/a.rpm" \
    "install foo;id" \
    "shell"; do
    # shellcheck disable=SC2086  # intentional word splitting of test cases
    if VNC_PKG_DRY_RUN=1 bash "$repo/container/vnc-pkg" $bad >/dev/null 2>&1; then
        fail "vnc-pkg reject" "should have rejected: $bad"
        bad_ok=0
    fi
done
[ "$bad_ok" -eq 1 ] && pass "vnc-pkg rejects invalid commands, flags, paths, and URLs"

# 11. d_pull: pulls from GHCR and retags locally, or tells user a local d_build is required
out=$(run_env "STUB_INSPECT=ed container=; source '$repo/env.rc'; d_target=gnome-agy d_pull" 2>&1)
if grep -Fq '[podman pull ghcr.io/edswarthout/vnc-desktop-ubuntu:gnome-antigravity-2604]' <<< "$out" \
   && grep -Fq '[podman tag ghcr.io/edswarthout/vnc-desktop-ubuntu:gnome-antigravity-2604 localhost/vnc-desktop-ubuntu:gnome-antigravity-2604]' <<< "$out" \
   && grep -Fq "image user is 'ed' (your d_user is 'tester')" <<< "$out"; then
    pass "d_pull pulls from GHCR (accepting gnome-agy), tags locally, and notes differing image user"
else
    fail "d_pull success" "got: $out"
fi

out=$(run_env "container=; source '$repo/env.rc'; d_registry=ghcr.io/fork/ d_target=gnome-claude d_pull" 2>&1)
if grep -Fq '[podman pull ghcr.io/fork/vnc-desktop-ubuntu:gnome-claude-2604]' <<< "$out" \
   && grep -Fq '[podman tag ghcr.io/fork/vnc-desktop-ubuntu:gnome-claude-2604 localhost/vnc-desktop-ubuntu:gnome-claude-2604]' <<< "$out"; then
    pass "d_pull respects d_registry override"
else
    fail "d_pull d_registry" "got: $out"
fi

out=$(run_env "STUB_PULL_FAIL=1 container=; source '$repo/env.rc'; d_target=lxqt d_pull" 2>&1 || true)
if grep -Fq 'a local d_build is required (d_distro=ubuntu d_target=lxqt d_build)' <<< "$out" \
   && ! grep -Fq '[podman tag ' <<< "$out"; then
    pass "d_pull reports local d_build is required when image is unavailable"
else
    fail "d_pull unavailable" "got: $out"
fi

if run_env "container=; source '$repo/env.rc'; d_distro=debian d_target=kde d_pull" >/dev/null 2>&1; then
    fail "d_pull invalid target" "expected debian+kde to fail"
else
    pass "d_pull rejects invalid distro+target"
fi

echo "$fails failed"
[ "$fails" -eq 0 ]
