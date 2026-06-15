"""
title: URL Fetcher Filter
author: local
version: 10.0.0
description: Fetches live URLs (including JS-rendered pages) and injects content before the model sees the message.
             Uses Kali fetch-proxy (Chromium 131, bypasses Cloudflare) with NixOS playwright fallback.
"""
from pydantic import BaseModel
import re, sys, os


class Filter:
    class Valves(BaseModel):
        kali_proxy_url: str = "http://192.168.174.128:9879/fetch"

    def __init__(self):
        self.valves = self.Valves()
        self.playwright_ws = "ws://127.0.0.1:13000"
        self.user_agent = (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        )

    async def fetch_via_kali_proxy(self, url: str) -> str | None:
        """Primary path: Kali fetch-proxy using Chromium 131 (passes Cloudflare TLS checks)."""
        proxy_url = self.valves.kali_proxy_url
        if not proxy_url:
            return None
        try:
            import httpx
            async with httpx.AsyncClient(timeout=60) as client:
                r = await client.post(proxy_url, json={"url": url})
                data = r.json()
                if data.get("error"):
                    return None
                content = data.get("content", "")
                if content:
                    return "[kali-proxy] " + content
        except Exception:
            pass
        return None

    async def fetch_via_playwright(self, url: str) -> str | None:
        """Fallback: NixOS playwright-server (may fail on Cloudflare-protected sites)."""
        try:
            from playwright.async_api import async_playwright
            async with async_playwright() as p:
                browser = await p.chromium.connect(endpoint=self.playwright_ws)
                ctx = await browser.new_context(
                    user_agent=self.user_agent,
                    viewport={"width": 1280, "height": 900},
                    locale="en-US",
                    timezone_id="America/New_York",
                    extra_http_headers={
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
                    },
                )
                page = await ctx.new_page()
                await page.add_init_script("""
                    Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
                    Object.defineProperty(navigator, 'languages', {get: () => ['en-US', 'en']});
                    Object.defineProperty(navigator, 'hardwareConcurrency', {get: () => 8});
                    Object.defineProperty(navigator, 'plugins', {get: () => [1,2,3,4,5]});
                    window.chrome = {runtime: {}};
                    const origQuery = window.navigator.permissions.query;
                    window.navigator.permissions.query = (p) =>
                        p.name === 'notifications'
                        ? Promise.resolve({state: Notification.permission})
                        : origQuery(p);
                """)
                await page.goto(url, wait_until="domcontentloaded", timeout=45000)
                await page.wait_for_timeout(5000)
                content = await page.inner_text("body")
                await ctx.close()
                await browser.close()
                return "[playwright-nixos] " + content[:24000]
        except Exception:
            pass
        return None

    async def fetch_url(self, url: str) -> str:
        result = await self.fetch_via_kali_proxy(url)
        if result:
            return result

        result = await self.fetch_via_playwright(url)
        if result:
            return result

        try:
            import httpx
            async with httpx.AsyncClient(follow_redirects=True, timeout=15) as client:
                r = await client.get(url, headers={"User-Agent": self.user_agent})
                return f"[httpx status={r.status_code}] " + r.text[:8000]
        except Exception as e:
            return f"[all_failed] python={sys.version.split()[0]} error={e}"

    async def inlet(self, body: dict, __user__: dict = None) -> dict:
        messages = body.get("messages", [])
        if not messages:
            return body
        last = messages[-1]
        if last.get("role") != "user":
            return body
        content = last.get("content", "")
        if not isinstance(content, str):
            return body
        urls = re.findall(r'https?://[^\s\)\]>"]+', content)
        if not urls:
            return body
        fetched_parts = []
        for url in urls[:2]:
            fetched = await self.fetch_url(url)
            fetched_parts.append(f"[Live fetch: {url}]\n{fetched}")
        if fetched_parts:
            last["content"] = content + "\n\n" + "\n\n".join(fetched_parts)
            messages[-1] = last
            body["messages"] = messages
        return body
