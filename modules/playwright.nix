{ config, pkgs, ... }:

{
  # Headless browser server — gives Open WebUI the ability to render
  # JavaScript-heavy pages (React SPAs, etc.) when loading URLs
  systemd.services.playwright-server = {
    enable      = true;
    description = "Playwright headless browser WebSocket server";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network.target" ];

    environment = {
      PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    };

    serviceConfig = {
      ExecStart = "${pkgs.nodejs}/bin/node ${pkgs.playwright-driver}/bin/playwright run-server --port 3000 --host 127.0.0.1";
      Restart   = "on-failure";
      User      = "t4x0r";
    };
  };
}
