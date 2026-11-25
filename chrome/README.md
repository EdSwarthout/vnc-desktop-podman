# Automating Chrome in an instance

How to drive the Chrome of an instance from outside it: from the host, or from a
parent instance for a nested one (`vnc-desktop-ubuntu-8` →
`vnc-desktop-ubuntu-8_vnc-desktop-ubuntu-1`). The helpers are in
[`env.rc`](env.rc) here, which the top-level `env.rc` sources. They work with every
image from `browser` on; the [image](#the-browser-image) built from the
[`Containerfile`](Containerfile) here adds Chrome Canary and the tools.

## Helpers

- **`d_chrome [URL...]`** starts Chrome on the selected instance's desktop with its
  DevTools (remote debugging) port open at `http://127.0.0.1:9222` (`d_chrome_port`)
  and waits until the port answers. If that Chrome is already running, the URLs open
  in it; started without a URL, it shows `chrome://version/` (version, command line
  and profile path of the browser you got). `d_chrome_bin=google-chrome-canary d_chrome` starts Canary instead, `d_chrome_bin=chromium` Chromium (Arch Linux's images) (own
  profile; give it another `d_chrome_port` to run both at once).
- **`d_chrome_mcp`** prints the command that registers that browser with Claude Code
  as MCP server `chrome-<instance>`. It only prints: the command changes your Claude
  Code configuration, so it's yours to run. It uses the image's `chrome-devtools-mcp`
  where there is one, and `npx -y chrome-devtools-mcp@latest` (downloaded into the
  instance's home at each start) otherwise.
- **`d_devtools COMMAND [ARGS...]`** is Chrome DevTools from the shell, on that
  browser: the `chrome-devtools` CLI of [Chrome DevTools for
  agents](https://developer.chrome.com/docs/devtools/agents/get-started), run in the
  instance (browser image only). Its commands are the MCP server's tools. It starts
  the CLI's daemon when needed; `d_devtools stop` ends it.
- **`d_test`** (top-level `env.rc`) checks "Chrome renders a page (headless)" for
  every image from `browser` on.

```bash
source env.rc; d_select 1; d_run
d_chrome https://example.com
d_exec curl -s http://127.0.0.1:9222/json/list      # the open pages, as JSON
d_chrome_mcp                                        # prints: claude mcp add chrome-vnc-desktop-ubuntu-1 -- podman exec -i vnc-desktop-ubuntu-1 …

# with the browser image (d_target=devtools):
d_devtools list_pages
d_devtools navigate_page 1 --url https://example.com
d_devtools take_snapshot 1                          # the page as an accessibility tree, with element uids
d_devtools take_screenshot 1 --fullPage --filePath shot.png     # lands in "$d_home"/shot.png
d_devtools --help
```

`d_chrome_mcp` and `d_devtools` give `chrome-devtools-mcp` the same options: attach
to `d_chrome`'s browser, `--no-usage-statistics` (it reports usage to Google
otherwise), `--performanceCrux=false` (performance traces otherwise send the pages'
URLs to Google's CrUX API, for field data) and `--workspace=/home/<user>` (where it
may read and write files; the default is only the temp directory). Add your own
with `d_devtools_opts`, e.g. `d_devtools_opts=(--performanceCrux)` or `(--categoryNetwork=false)`.

## The browser image

`d_target=devtools` selects [`Containerfile`](Containerfile) here: Ubuntu's `browser`
stage (stable Chrome, TigerVNC/noVNC, nested podman, the CLI installers) plus, in its
stage `ubuntu`, image `vnc-desktop-ubuntu:devtools`:

- **Google Chrome Canary** (`google-chrome-canary`, from the apt repository that the
  stable Chrome set up), behind the same `--no-sandbox` wrapper as stable. Stable
  stays the default browser.
- **npm tools in the image** (`/usr/local`, on `NODE_PATH`), so nothing is downloaded
  and run at use time: `chrome-devtools-mcp` (the MCP server, the `chrome-devtools`
  CLI and agent skills) and `@playwright/mcp` (MCP server),
  `puppeteer-core` and `playwright-core` (for scripts: `require("puppeteer-core")`
  works anywhere), `lighthouse` (page audits). None brings a browser of its own:
  they attach to the one `d_chrome` started.
- **Python**: `uv` (`/opt/uv/bin`) and a virtual environment (`/opt/venv`) with
  `playwright`, both owned by the user. The venv is first on `PATH`, so `python3`
  finds `playwright`, and `uv pip install NAME` adds packages without root (they
  last until the instance is replaced; add them to the `Containerfile` to keep them).
- **`install_chrome_devtools`**, for a Claude Code running *in* the instance
  (`install_claude`): copies the skills that `chrome-devtools-mcp` ships (using the
  CLI, debugging accessibility, cookies, LCP, memory leaks, troubleshooting) to
  `~/.claude/skills` and prints the `claude mcp add` line. Usage statistics and
  update checks of `chrome-devtools-mcp` are off in the image's environment.
  A browser it launches itself needs `--chromeArg=--no-sandbox` in a container;
  attaching to one from `d_chrome` (`--browserUrl`) doesn't.
- **Openbox** as window manager (the session is Openbox + an xterm; closing the
  xterm stops the container), `scrot` (screenshots), `socat` (relays), `ffmpeg`
  (video from screenshots or the display).

```bash
d_target=devtools d_build                    # builds vnc-desktop-ubuntu:browser first
d_select 1; d_target=devtools d_run          # vnc-desktop-ubuntu-devtools-1, VNC 7001, noVNC 6181
d_target=devtools d_chrome_bin=google-chrome-canary d_chrome https://example.com
d_target=devtools d_exec node my-script.js   # a Puppeteer/Playwright script in the home
cp chrome/search_screenshot.py "$d_home"/    # the example below
d_target=devtools d_exec python3 search_screenshot.py "rootless podman" -o search.png
d_test 20 devtools                           # the usual checks
```
The versions of Canary, the npm tools, `uv` and `playwright` are whatever is current
when the layer is built; `d_build_fresh` renews them.

[`search_screenshot.py`](search_screenshot.py) is an example for Python: it opens a
tab in the browser `d_chrome` started, does a web search (`--engine duckduckgo` |
`bing` | `google`), saves the results page as a PNG (`--full-page` for all of it)
and closes the tab. Where no results appear (a consent or robot check) it saves the
page as it is and exits 1.

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
| **MCP server in the instance**: `podman exec -i <instance> chrome-devtools-mcp --browserUrl http://127.0.0.1:9222` (or `playwright-mcp --cdp-endpoint …`), registered with Claude Code | stdio through `podman exec`; no port | `d_chrome`; the browser image, or an npm download into the instance's home at each start | Recommended for interactive use (navigate, click, read DOM, console and network, page screenshots, Lighthouse, performance traces). |
| **Script in the instance**: `d_exec node script.js` with `puppeteer-core` or `playwright-core` attached to the port | same | `d_chrome`; the browser image, or `npm install` of one package in the instance's home (no root needed) | For repeatable checks that need interaction. |
| **Headless one-shots**: `google-chrome --headless --dump-dom URL`, `--screenshot=FILE URL` | `d_exec` | nothing | In `d_test`. No dependencies, no interaction, not the visible browser. |
| **Client outside, over a published port** | an extra `-p` in `d_run` plus a relay in the instance (Chrome won't listen on other addresses) | changing `d_run`, recreating instances | Skip: more moving parts, and browser control on a port. |
| **`xdotool` + screenshots** (`tests/screenshot.sh`) | `d_exec` | nothing (stage `vnc` has `xdotool`) | For what's outside the page: dialogs, the browser's own UI, other apps. Blind: coordinates and timing, no DOM. |
| **Claude in Chrome extension** in the instance | the extension's own channel | installing and signing in the extension in that profile | For a long-lived instance used as a personal browser; not for throwaway ones. |
| **Selenium / chromedriver** | `d_exec` | a `chromedriver` matching Chrome's version | Skip: nothing the script option doesn't do with less setup. |

The other images need no change for the first three: Chrome, Node 22 and npm are
already there (`nodejs` and `npm` are in `base`); the browser image only saves the
downloads.

## What has been tried (2026-11-16, nested in an Ubuntu instance)

- `d_chrome` on a Ubuntu `gnome` instance (Chrome 157): the port answered, `/json/list`
  showed the pages, a second `d_chrome URL` opened in the same browser. Not run on Debian.
- The headless check in `d_test`: passes on Ubuntu and Debian `gnome` and on `devtools`.
- The browser image: `d_test` passes all its checks. With Canary 160 started by
  `d_chrome`: a `puppeteer-core` script read the page and saved a page screenshot,
  `playwright-core` connected over CDP and read the title, and `chrome-devtools-mcp`
  1.13 answered `initialize`, `tools/list` (33 tools) and a `list_pages` call over
  `podman exec -i`, with the flags `d_chrome_mcp` prints.
- `search_screenshot.py` with the image's `python3` (uv venv) against Canary:
  a DuckDuckGo search saved as PNG. Bing and Google not tried.
- `d_devtools` against Canary: `list_pages` and `take_screenshot` (the PNG arrived
  in the home), the daemon starting on first use; `install_chrome_devtools` copied
  the seven skills.
- **Not tried:** the skills in use, Claude Code's plugin route
  (`/plugin marketplace add ChromeDevTools/chrome-devtools-mcp`, which runs the
  server and a browser where Claude Code runs, not in a child instance),
  the MCP server registered in a real Claude Code session,
  `playwright-mcp`, `lighthouse` and `ffmpeg` beyond `--version`, the `npx` variant
  on the other images, and any of this on the host.

## Sources

- [Changes to remote debugging switches to improve security](https://developer.chrome.com/blog/remote-debugging-port) (Chrome 136)
- [Chrome DevTools MCP configuration](https://developer.chrome.com/docs/devtools/agents/get-started/configuration)
- [Playwright MCP configuration](https://playwright.dev/mcp/configuration/browser-extension)
