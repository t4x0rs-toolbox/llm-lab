"""
title: URL Fetcher Filter
author: local
version: 11.0.0
description: Fetches live URLs (including JS-rendered SPAs) and injects content before
             the model sees the message. Launches Chromium directly — no external proxy needed.
"""
import re, sys, os


class Filter:
    def __init__(self):
        self.user_agent = (
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        )

    async def fetch_url(self, url: str) -> str:
        # CHROMIUM_PATH: set in open-webui.nix → ${pkgs.chromium}/bin/chromium
        # Falls back to playwright's own bundled browser if unset.
        chromium_path = os.environ.get("CHROMIUM_PATH") or None

        try:
            from playwright.async_api import async_playwright
            async with async_playwright() as p:
                browser = await p.chromium.launch(
                    executable_path=chromium_path,
                    headless=True,
                    args=[
                        "--no-sandbox",
                        "--disable-setuid-sandbox",
                        "--disable-dev-shm-usage",
                        # Disable the automation flag at the browser level — stronger
                        # than patching navigator.webdriver in JS.
                        "--disable-blink-features=AutomationControlled",
                    ],
                )
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
                    try {
                        const orig = window.navigator.permissions.query;
                        window.navigator.permissions.query = (p) =>
                            p.name === 'notifications'
                            ? Promise.resolve({state: Notification.permission})
                            : orig(p);
                    } catch(e) {}
                """)
                # domcontentloaded + explicit wait is required for React/Vue SPAs.
                # networkidle cuts off before the framework hydrates and renders lists.
                await page.goto(url, wait_until="domcontentloaded", timeout=45000)
                await page.wait_for_timeout(5000)
                content = await page.inner_text("body")
                await ctx.close()
                await browser.close()
                return "[chromium] " + content[:24000]
        except Exception as e:
            err = str(e)

        # Fallback: plain HTTP (works for non-JS sites)
        try:
            import httpx
            async with httpx.AsyncClient(follow_redirects=True, timeout=15) as client:
                r = await client.get(url, headers={"User-Agent": self.user_agent})
                return f"[httpx {r.status_code}] " + r.text[:8000]
        except Exception as e2:
            pyver = sys.version.split()[0]
            return f"[failed] chromium_err={err} httpx_err={e2} python={pyver}"

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
