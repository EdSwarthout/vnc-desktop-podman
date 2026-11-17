# Automating Chrome in an instance

How to drive the Chrome of an instance from outside it: from the host, or from a
parent instance for a nested one (`cc8u` → `cc8u_1u`). The helpers are in
[`env.rc`](env.rc) here, which the top-level `env.rc` sources.

## Helpers

- **`d_chrome [URL...]`** starts Chrome on the selected instance's desktop with its
  DevTools (remote debugging) port open at `http://127.0.0.1:9222` (`d_chrome_port`)
  and waits until the port answers. If that Chrome is already running, the URLs open
  in it.
- **`d_chrome_mcp`** prints the command that registers that browser with Claude Code
  as MCP server `chrome-<instance>`. It only prints: the command changes your Claude
  Code configuration and runs an npm package, so it's yours to run.
- **`d_test`** (top-level `env.rc`) checks "Chrome renders a page (headless)" for
  every stage from `chrome` on.

```bash
source env.rc; d_select 1; d_run
d_chrome https://example.com
d_exec curl -s http://127.0.0.1:9222/json/list      # the open pages, as JSON
d_chrome_mcp                                        # prints: claude mcp add chrome-cc1u -- podman exec -i cc1u …
```

## Two things that shape everything

- **Chrome ignores `--remote-debugging-port` on its default profile** (since Chrome
  136). It needs `--user-data-dir` pointing somewhere else, so `d_chrome` uses
  `~/.config/chrome-automation`: a separate profile from the one the menu's Chrome
  uses (`~/.config/google-chrome`), with its own logins, bookmarks and extensions.
- **The port listens on the instance's `127.0.0.1` only**, and `d_run` publishes only
  the VNC and noVNC ports. So the client runs *inside* the instance, started with
  `d_exec` or `podman exec -i`, and is spoken to over its stdin/stdout. No port
  leaves the instance. Anything that can reach the port controls the browser,
  logins included, which is a reason to keep it that way.

## Options

| Option | How it reaches Chrome | Needs | Verdict |
|---|---|---|---|
| **MCP server in the instance**: `podman exec -i <instance> npx chrome-devtools-mcp --browserUrl http://127.0.0.1:9222` (or `@playwright/mcp --cdp-endpoint …`), registered with Claude Code | stdio through `podman exec`; no port | `d_chrome`; an npm download into the instance's home on first use | Recommended for interactive use (navigate, click, read DOM, console and network, page screenshots). **Not tested yet**, see below. |
| **Script in the instance**: `d_exec node script.js` with `puppeteer-core` or `playwright-core` attached to the port | same | `d_chrome`; `npm install` of one package in the instance's home (no root needed) | For repeatable checks that need interaction. |
| **Headless one-shots**: `google-chrome --headless --dump-dom URL`, `--screenshot=FILE URL` | `d_exec` | nothing | In `d_test`. No dependencies, no interaction, not the visible browser. |
| **Client outside, over a published port** | an extra `-p` in `d_run` plus a relay in the instance (Chrome won't listen on other addresses) | changing `d_run`, recreating instances | Skip: more moving parts, and browser control on a port. |
| **`xdotool` + screenshots** (`tests/screenshot.sh`) | `d_exec` | nothing (stage `vnc` has `xdotool`) | For what's outside the page: dialogs, the browser's own UI, other apps. Blind: coordinates and timing, no DOM. |
| **Claude in Chrome extension** in the instance | the extension's own channel | installing and signing in the extension in that profile | For a long-lived instance used as a personal browser; not for throwaway ones. |
| **Selenium / chromedriver** | `d_exec` | a `chromedriver` matching Chrome's version | Skip: nothing the script option doesn't do with less setup. |

The images need no change for any of the first three: Chrome, Node 22 and npm are
already there (`nodejs` and `npm` are in `base`).

## What has been tried (2026-11-16, Chrome 157, nested in `cc8u`)

- `d_chrome` on a Ubuntu `gnome` instance: the port answered, `/json/list` showed the
  pages, a second `d_chrome URL` opened in the same browser. Not run on Debian.
- The headless check in `d_test`: passes on Ubuntu and Debian `gnome`.
- **Not tried: the MCP server.** Whether `chrome-devtools-mcp` starts in an instance,
  and whether `--browserUrl` is the right spelling of its flag, is unconfirmed. To
  try it: `d_run` an instance, `d_chrome`, run the line `d_chrome_mcp` prints, then
  restart Claude Code so it loads the server.
- Not tried either: a Puppeteer or Playwright script, `@playwright/mcp`, and any of
  this on the host.

## Sources

- [Changes to remote debugging switches to improve security](https://developer.chrome.com/blog/remote-debugging-port) (Chrome 136)
- [Chrome DevTools MCP configuration](https://developer.chrome.com/docs/devtools/agents/get-started/configuration)
- [Playwright MCP configuration](https://playwright.dev/mcp/configuration/browser-extension)
