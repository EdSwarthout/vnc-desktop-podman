#!/usr/bin/env python3
"""Do a web search in a running Chrome and save the results page as a PNG.

Runs inside an instance, next to a Chrome started with the DevTools port (d_chrome):
it opens a new tab in that browser, so you can watch it over VNC, searches, takes the
screenshot and closes the tab again.

    search_screenshot.py "podman rootless" -o results.png
    search_screenshot.py "podman rootless" --engine google --full-page --keep

Needs the Python package playwright (the library only, no browser download). The
browser image (vnc-desktop-ubuntu:devtools) has it; in another one, in the instance:
    python3 -m venv ~/.venvs/pw && ~/.venvs/pw/bin/pip install playwright
    ~/.venvs/pw/bin/python search_screenshot.py "..."
"""
import argparse
import sys
from urllib.parse import quote_plus

from playwright.sync_api import Error, sync_playwright

# engine: (search URL, CSS selector of a result, which shows the results have loaded)
ENGINES = {
    "duckduckgo": ("https://duckduckgo.com/?q={}", "[data-testid=result], article"),
    "bing": ("https://www.bing.com/search?q={}", "#b_results .b_algo"),
    "google": ("https://www.google.com/search?q={}", "#search a h3"),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("query", help="what to search for")
    ap.add_argument("-o", "--output", default="search.png", help="PNG to write (default: %(default)s)")
    ap.add_argument("--engine", choices=ENGINES, default="duckduckgo", help="default: %(default)s")
    ap.add_argument("--cdp", default="http://127.0.0.1:9222", help="Chrome's DevTools address (default: %(default)s)")
    ap.add_argument("--full-page", action="store_true", help="the whole page, not just the visible part")
    ap.add_argument("--keep", action="store_true", help="leave the tab open")
    ap.add_argument("--timeout", type=float, default=20, help="seconds to wait for results (default: %(default)s)")
    args = ap.parse_args()

    url, result = ENGINES[args.engine]
    with sync_playwright() as p:
        try:
            browser = p.chromium.connect_over_cdp(args.cdp)
        except Error as e:
            sys.exit(f"no Chrome at {args.cdp} (start one with d_chrome): {e.message.splitlines()[0]}")
        page = browser.contexts[0].new_page()
        page.goto(url.format(quote_plus(args.query)), wait_until="domcontentloaded")
        found = True
        try:
            page.wait_for_selector(result, timeout=args.timeout * 1000)
        except Error:
            # e.g. a consent page or a "are you a robot" check: the picture shows which
            found = False
            print(f"no search results appeared within {args.timeout:g} s; saving the page as it is", file=sys.stderr)
        page.wait_for_timeout(500)  # let images and fonts settle
        page.screenshot(path=args.output, full_page=args.full_page)
        print(f"{args.output}: {page.title()} ({page.url})")
        if not args.keep:
            page.close()
        # Only disconnects: the browser was started by someone else and stays up.
        browser.close()
    return 0 if found else 1


if __name__ == "__main__":
    sys.exit(main())
