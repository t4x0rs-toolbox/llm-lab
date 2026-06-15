#!/usr/bin/env python3
"""
fetch-proxy.py — Playwright-based URL fetch proxy for Open WebUI filter.
Runs on Kali, called by the URL Fetcher Filter on NixOS.

Usage: python3 fetch-proxy.py [--port 9879] [--host 0.0.0.0]
POST /fetch  {"url": "https://..."}  → {"content": "...", "error": null}
GET  /health → {"status": "ok"}
"""
import asyncio
import argparse
import json
import os
import sys
from aiohttp import web

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)

STEALTH_SCRIPT = """
    Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
    Object.defineProperty(navigator, 'languages', {get: () => ['en-US', 'en']});
    Object.defineProperty(navigator, 'hardwareConcurrency', {get: () => 8});
    Object.defineProperty(navigator, 'plugins', {get: () => [1,2,3,4,5]});
    window.chrome = {runtime: {}};
    try {
        const origQuery = window.navigator.permissions.query;
        window.navigator.permissions.query = (p) =>
            p.name === 'notifications'
            ? Promise.resolve({state: Notification.permission})
            : origQuery(p);
    } catch(e) {}
"""

EXTRA_HEADERS = {
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate, br",
    "DNT": "1",
    "Upgrade-Insecure-Requests": "1",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "none",
    "Sec-Fetch-User": "?1",
    "Cache-Control": "max-age=0",
}


async def fetch_url(url: str) -> tuple[str, str | None]:
    """Returns (content, error). content is empty string on error."""
    try:
        from playwright.async_api import async_playwright

        async with async_playwright() as p:
            browser = await p.chromium.launch(
                headless=True,
                executable_path="/usr/lib/chromium/chromium",
                args=[
                    "--no-sandbox",
                    "--disable-setuid-sandbox",
                    "--disable-dev-shm-usage",
                    "--disable-blink-features=AutomationControlled",
                ],
            )
            ctx = await browser.new_context(
                user_agent=USER_AGENT,
                viewport={"width": 1280, "height": 900},
                locale="en-US",
                timezone_id="America/New_York",
                extra_http_headers=EXTRA_HEADERS,
            )
            page = await ctx.new_page()
            await page.add_init_script(STEALTH_SCRIPT)
            await page.goto(url, wait_until="domcontentloaded", timeout=45000)
            await page.wait_for_timeout(5000)
            content = await page.inner_text("body")
            await ctx.close()
            await browser.close()
            return content[:32000], None
    except Exception as e:
        return "", str(e)


async def handle_fetch(request: web.Request) -> web.Response:
    try:
        body = await request.json()
        url = body.get("url", "").strip()
    except Exception:
        return web.json_response({"content": "", "error": "invalid JSON body"}, status=400)

    if not url.startswith("http"):
        return web.json_response({"content": "", "error": f"bad url: {url!r}"}, status=400)

    content, error = await fetch_url(url)
    return web.json_response({"content": content, "error": error})


async def handle_health(request: web.Request) -> web.Response:
    return web.json_response({"status": "ok", "chromium": "/usr/lib/chromium/chromium"})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=9879)
    parser.add_argument("--host", default="0.0.0.0")
    args = parser.parse_args()

    app = web.Application()
    app.router.add_post("/fetch", handle_fetch)
    app.router.add_get("/health", handle_health)

    print(f"fetch-proxy listening on {args.host}:{args.port}", flush=True)
    web.run_app(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
