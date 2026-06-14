{ config, pkgs, ... }:

let
  # open-webui's bundled Python env doesn't include playwright.
  # Inject it via PYTHONPATH so langchain_community can import it.
  pythonWithPlaywright = pkgs.python3.withPackages (ps: [ ps.playwright ]);
in
{
  services.open-webui = {
    enable      = true;
    host        = "0.0.0.0";
    port        = 8888;
    openFirewall = true;

    environment = {
      OLLAMA_BASE_URL = "http://127.0.0.1:11500";
      WEBUI_AUTH      = "False";

      RAG_EMBEDDING_ENGINE = "ollama";
      RAG_OLLAMA_BASE_URL  = "http://127.0.0.1:11500";
      RAG_EMBEDDING_MODEL  = "nomic-embed-text";

      CHUNK_SIZE    = "1500";
      CHUNK_OVERLAP = "200";

      WEB_LOADER_ENGINE = "playwright";
      PLAYWRIGHT_WS_URL = "ws://127.0.0.1:13000";

      # Make playwright importable inside open-webui's Python process
      PYTHONPATH                   = "${pythonWithPlaywright}/lib/python3.13/site-packages";
      PLAYWRIGHT_BROWSERS_PATH     = "${pkgs.playwright-driver.browsers}";
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    };
  };
}
