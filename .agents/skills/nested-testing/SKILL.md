---
name: nested-testing
description: >-
  Runbook for building, running, inspecting, and testing vnc-desktop-podman changes from
  inside a running container instance using nested rootless podman and stubbed-podman unit
  tests. Use whenever verifying Containerfile, env.rc, desktop, or runtime script changes.
---

# Testing Changes from Inside an Instance

Inside an instance you are non-root (sudoers allows only `nested-subids ""` and
`vnc-pkg`), and images ship without package lists. When `$container` is set, `env.rc`
automatically targets nested podman (`~/Containers/<parent>_<name>`,
`/var/cache/apt-<distro>` cache mounts, no `--hostname`, copies parent's VNC password when
`$VNC_PASSWORD` is unset).

## 1. Fast checks (no container build)
Always run these after editing shell scripts or `env.rc`:
```bash
shellcheck -s bash env.rc chrome/env.rc container/start.sh container/vnc-pkg \
    container/vncserver-wrapper container/nested-subids container/cli-installers/* \
    tests/tests.sh tests/screenshot.sh tests/lock.sh tests/test_env.sh
shellcheck -s sh container/opencode/setup-opencode.sh
bash tests/test_env.sh
```

## 2. Full automated target test (`d_test`)
Pick an unused instance number `N` (check `podman ps -a` and `ls ~/Containers`):
```bash
source ./env.rc
d_distro=ubuntu d_test 1 lxqt               # builds, runs, checks, removes
d_distro=ubuntu d_test_keep=1 d_test 1 lxqt # leaves container running afterwards
```
- Logs and screenshots land in `/tmp/d_test/<instance>-<target>.{build.log,log,png}`.
- Always inspect the screenshot PNG and check `.build.log` for unconsumed build-arg
  warnings.
- `d_test` verifies: build, startup, `tests/tests.sh` (nested podman), no `VNC_PASSWORD`
  in `podman inspect` or `/proc/*/environ`, `sudo -n true` refused, shared apt caches
  mounted, noVNC on `127.0.0.1` and `[::1]`, headless Chrome/Chromium render, screenshot,
  `tests/lock.sh`, session logout stopping the container, and `podman start` recovery.

## 3. Manual / interactive nested debugging
```bash
source ./env.rc
d_target=<target> d_build > /tmp/build.log 2>&1
d_run_new                                   # picks next free N; prints $d_name & $d_home
d_target=<target> d_run
```
- `$d_home` (`~/Containers/<name>`) is directly readable/writable on the parent: copy files
  with plain `cp`, no `podman cp` needed.
- Take a screenshot (after 15–40 s for desktop startup):
  ```bash
  cp tests/screenshot.sh "$d_home/"
  d_exec bash "/home/$d_user/screenshot.sh" "/home/$d_user/s.png"
  # then inspect "$d_home/s.png"
  ```
- Launch GUI apps with the desktop's session bus and stripped ambient caps:
  `d_exec -s -d <app>` (never plain `podman exec -d`, which retains ambient `NET_RAW` and
  breaks `bwrap`/GTK icons).
- Experiment as root inside a throwaway nested container before editing a Containerfile:
  `podman exec -u root "$d_name" sh -c 'apt-get update && apt-get install -y PKG'`
  (Fedora: `dnf install -y PKG`; Arch: `pacman -Syu --needed PKG`).
- Query packages without a running instance:
  - Ubuntu/Debian: `podman run --rm --user root vnc-desktop-ubuntu:browser-2604 sh -c 'apt-get update -qq; apt-cache policy PKG'`
  - Fedora: `podman run --rm --user root -v /var/cache/apt-fedora:/var/cache/apt-fedora --security-opt label=disable registry.fedoraproject.org/fedora:45 dnf repoquery --setopt=system_cachedir=/var/cache/apt-fedora PKG`

## 4. Cleanup
Always clean up throwaway containers unless the user asked to leave them running:
```bash
d_distro=<distro> d_target=<target> d_rm -f N
podman ps -a
```
(`d_rm` retries `podman rm -f -t 2` for occasional `openByHandleAt` errors and uses
`podman unshare rm -rf` for sub-ID-owned nested container storage.)

## 5. Limits of nested testing
Real host paths, NFS-mounted package caches, different host UID/GIDs, and host-level
`pids.max` cannot be verified from inside an instance. State clearly what was tested
nested vs what remains for the user to verify on the host.
