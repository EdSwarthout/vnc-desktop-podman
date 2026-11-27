# PLAN.md vs PLAN-cc.md (research/wayland): comparison and follow-up

## Context
The user asked for a review of `research/wayland/PLAN.md` (`9d982cd`, written earlier on
this branch by another agent) against `research/wayland/PLAN-cc.md` (`07276ff`, mine), and
for insights. Both plans start from the same research (`research-20261117`). This file
holds the comparison, plus a small follow-up edit that folds PLAN.md's strong points into
PLAN-cc.md.

## Where they agree
- Drop vkms/KMS for GNOME. Use headless GNOME Shell 50 with a private system bus and the
  mock logind.
- Two tracks, GNOME Shell and labwc + wayvnc, both built on `browser` first. Omarchy is
  deferred.
- 7450+N for RDP, respecting `d_bind`. No passwords in the container env. Experiments in
  throwaway nested instances before any wiring.

## What PLAN-cc.md adds or fixes in PLAN.md
1. **Target name bug**: PLAN.md's `gnome-wayland` would be read as desktop `gnome` + agent
   `wayland` (`env.rc:243`, `_d_layer=${d_target##*-}`). That makes it unbuildable without
   changing env.rc. PLAN-cc uses `gnomewl`.
2. **Browser access is decided**: PLAN.md leaves GNOME RDP-only, with browser access and
   screenshots open ("PipeWire/gst, frame capture, portal…"). PLAN-cc's bridge (a
   full-screen xfreerdp3 on Xvnc `:1`) keeps noVNC, `d_vnc`, `d_novnc`, `scrot`,
   `xdotool`, `_d_wait_ready` and `session_end` working unchanged. That turns three
   PLAN.md gaps (browser UI, screenshots, readiness) into one design.
3. **grd mode**: PLAN.md picks headless grd (a monitor per client). With the bridge and an
   external RDP client together, that gives two different screens. PLAN-cc uses mirror
   mode (shared screen, like VNC `-Shared`). The price is the keyring and a fixed
   resolution. Headless mode is the better choice *only* for an RDP-only design (each
   client resizes freely, no keyring).
4. **RDP daemon lifetime**: PLAN.md ends the session when "the shell or RDP daemon exits",
   so a client with the clipboard on would crash grd and stop the container. PLAN-cc
   restarts grd and ends only with gnome-shell.
5. **wayvnc auth**: PLAN.md says "TLS/VNC password". wayvnc has no VncAuth, only a user
   name and password over RSA-AES or TLS. PLAN-cc says so, and keeps the TigerVNC
   `passwd` for the helpers.
6. **Port slip**: PLAN.md's labwc websockify points at `127.0.0.1:5900`. `start.sh`
   uses 5901, and PLAN-cc keeps 5901.
7. **Password lifecycle**: PLAN.md consumes and deletes `rdp-pass.init`, but grd keeps the
   credentials in plaintext anyway (`credentials.ini` or the keyring). It also needs a new
   `d_run` writer. PLAN-cc derives the password from the existing `passwd.init` (one
   password for VNC and RDP). It has to stay in a file because the bridge needs it at
   every boot.
8. **Helpers named**: PLAN-cc lists each X-only helper to change (`start.sh` branch,
   `_d_session_sh`, `d_exec -s` env list, `_d_wait_ready`, `lock.sh`, `session_end`).
   PLAN.md says "wire into env.rc/tests".
9. **Small error in PLAN.md**: "branched from `main` at `eed45b9`". `eed45b9` is this
   branch's own AGENTS.md commit; the base on main is `eb0f1f3`.

## What PLAN.md has that PLAN-cc.md lacks (worth taking over)
1. **Host/GPU matrix and the safety rule**: hwd23 has `renderD128` = Intel and
   `renderD129` = NVIDIA; on the DGX Spark, `renderD128` is the NVIDIA GB10. Never
   hard-code `renderD128`. PLAN-cc's line "a render node added to `d_run_opts` by hand
   should just work" is wrong on the Spark. It needs that caveat.
2. **Electron agents over Xwayland** in Phase 1 (Antigravity, OpenCode; Claude Desktop
   stays `gnome`-only). That's the reason Xwayland matters, and PLAN-cc only tests "an X
   client and Chrome".
3. **Server-side clipboard fix as a goal**: PLAN-cc only works around the clipboard
   abort (bridge `-clipboard` plus restart). External clients would still crash grd on
   connect. Phase 1 should look for a server-side switch, or check whether `/dev/fuse`
   at the top level lets `fusermount3` work.
4. **Why labwc, not sway**: Arch's sway has `cap_sys_nice=ep`, a file cap that breaks
   under nested podman; aquamarine needs `xdg_wm_base` v6.
5. **An optional zero-GPU labwc check on Debian/Fedora** in Phase 1.
6. **`vnc-pkg` in the `d_test` checklist** for the new images.

## Weak points in both
- Neither checks how Super and other chords get through the double path (noVNC/RDP for
  gnomewl). The Omarchy notes show Super+Space getting lost through nested viewers.
  Add it to Phase 1 (PLAN-cc's step 4 checks Super, but not Super+Space or the overview
  key specifically).
- Neither estimates image size or the CPU cost of GNOME headless + grd + Xvnc per
  instance. Measure `pids.current` and RSS in Phase 1 (KDE alone is ~550 threads against
  `pids.max`).
- Both assume Ubuntu 26.04 ships `wayvnc`, `labwc` and `freerdp3-x11` on arm64. That's
  proven for freerdp3 only.

## Follow-up edit (applied in ./PLAN-cc-2.md; ./PLAN-cc.md is kept unchanged)
In `.claude/worktrees/wayland/research/wayland/PLAN-cc.md`:
- Remove the empty first line.
- §2 intro: replace "should just work" with the GPU caveat, and add a short host
  matrix: hwd23 Intel `renderD128` only, never `card*` or `renderD129`; Spark CPU only
  (`renderD128` is NVIDIA); Debian 13 / no vkms: CPU.
- §1 "Gaps in ./PLAN.md": add the 5900/5901 slip, the grd-exit stop and the `eed45b9`
  base note.
- Phase 1: add the Electron agents over Xwayland, the server-side clipboard fix,
  Super+Space through the bridge, resource use (pids, RSS), arm64 availability of
  labwc/wayvnc, and the optional Debian/Fedora labwc pixman check.
- labwc design: one line on why labwc and not sway.
- Phase 2/3 checks: add `vnc-pkg`.
- Status line: "supersedes ./PLAN.md where they differ". PLAN.md itself stays unchanged.

Don't commit unless asked (the user asked for the last commit explicitly; ask again).

## Verification
- `git -C .claude/worktrees/wayland diff --stat` shows only PLAN-cc.md.
- `grep -n 'renderD129\|5901\|Super+Space\|vnc-pkg' research/wayland/PLAN-cc.md` finds
  the new lines.
