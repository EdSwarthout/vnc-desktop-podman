# Draft: aquamarine Wayland-backend bugs (not submitted)

Status: **draft, not submitted** (2026-11-22). Found while nesting Hyprland in a headless
labwc for [intel-igpu-render-node.md](intel-igpu-render-node.md). Omarchy 4.5.0 pins
Hyprland 0.56.2 / aquamarine 0.15.1.

## Upstream status, checked 2026-11-22

Before writing anything, aquamarine's issues and its `main` and `v0.16.0` sources were
checked (`src/backend/Wayland.cpp`):

| # | Bug seen with 0.15.1 | Upstream | Report? |
|---|---|---|---|
| 1 | The output's first `wl_surface.commit` isn't flushed, and `newOutput` sits in `idleCallbacks`, which drain only when the parent sends an event. A quiet headless parent leaves Hyprland with no monitor. | **Fixed in v0.16.0** (2026-11-01): `createOutput()` now does `wl_display_flush()` ("Start the configure handshake even when there is no other host traffic"). | No |
| 2 | `events.frame` is emitted from the `xdg_toplevel.configure` handler, before `xdg_surface.configure` is acked. If the consumer already has the output, it commits a buffer first, and the parent kills the client (`xdg_surface has never been configured`). | **Fixed in v0.16.0**: the toplevel handler only stores `pendingSize`; `xdg_surface.configure` acks, then `applyConfigure()`. Probably "wayland: fix configure not applying sometimes (#415)", 2026-09-22. | No |
| 3 | `wl_registry_bind` at fixed versions: `wl_seat` 9, `xdg_wm_base` 6, `wl_compositor` 6, `zwp_linux_dmabuf_v1` 4 (and `wl_shm` 1). A parent that advertises less (wlroots 0.20 compositors such as sway 1.12, and weston 15: `xdg_wm_base` v5) disconnects the client: `invalid version for global xdg_wm_base (13): expected at most 5, got 6`. | **Known**: issue #398 (same case: Omarchy, nested in headless sway), **closed as not planned** 2026-09-12. A clamp PR (#427, `std::min(version, N)` on the binds) was auto-closed: Hypr projects take PRs only from vouched contributors. **Still in `main` and v0.16.0.** | Your call (below) |

## Recommendation

- **Don't file 1 or 2.** They're fixed upstream; they reach Omarchy when it moves past
  aquamarine 0.15.1. Then recheck `../omarchy/omarchy-session`'s workarounds (the `wtype`
  nudge, the disabled start + `hyprctl reload`). They should become unnecessary, though
  probably harmless.
- **3 is a duplicate of a closed issue.** A new issue would probably be closed the same
  way. If anything, a short comment on #398 adding the facts it may lack: weston 15 too,
  and that the binds exceed the advertised version, which the protocol forbids. The draft
  below is that comment. Our setup doesn't need the fix: labwc 0.20.2 advertises v6.
- Posting needs your GitHub account; don't include host names or paths.

## Draft comment for hyprwm/aquamarine#398

> Still reproducible with aquamarine 0.15.1 (Hyprland 0.56.2) and on current `main`:
> `CWaylandBackend::start()` binds `xdg_wm_base` at 6, `wl_compositor` at 6, `wl_seat`
> at 9 and `zwp_linux_dmabuf_v1` at 4 whatever the parent advertises. Binding above the
> advertised version is a protocol error (wl_registry.bind: the version must not exceed
> the advertised one), so the parent drops the client:
>
> ```
> wl_registry#2: error 0: invalid version for global xdg_wm_base (13): expected at most 5, got 6
> ```
>
> Parents that advertise `xdg_wm_base` v5 today: sway 1.12 (wlroots 0.20) and weston 15
> (headless backend). labwc 0.20.2 advertises v6, so nesting under it works.
>
> The usual client idiom is to bind at `std::min(version, N)` and check the bound
> version where newer requests are used (`xdg_wm_base` v6 only adds
> `xdg_toplevel.wm_capabilities`, an event, so v5 needs no other change).
>
> Repro: `WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 sway` (or `weston
> --backend=headless`), then `WAYLAND_DISPLAY=<its socket> Hyprland`.

## Optional: draft new issue (only if #398 is deemed the wrong place)

**Title:** Wayland backend: `wl_registry_bind` above the advertised version (`xdg_wm_base` 6 vs 5) kills nested sessions

**Body:** the comment above, plus:

> Versions: aquamarine 0.15.1 and `main` (`src/backend/Wayland.cpp`, `start()`'s
> registry listener). Related: #398 (closed as not planned). This is a protocol
> violation, not a feature request, so it seemed worth raising again.

## How the facts were checked

- 0.15.1 behaviour: Hyprland 0.56.2 in a container, with sway 1.12, weston 15.0.1 and
  labwc 0.20.2 headless on the Intel iGPU render node. `wayland-info` showed each
  parent's `xdg_wm_base` version (labwc 6, weston 5, sway 5). `WAYLAND_DEBUG` on both
  sides showed the unflushed commit and the `wl_display.error`.
- Upstream code: `src/backend/Wayland.cpp` at tags `v0.15.1` and `v0.16.0` and at `main`,
  from raw.githubusercontent.com. Issues and PRs: the GitHub REST API, read without an
  account.
