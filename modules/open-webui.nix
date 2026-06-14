{ config, pkgs, ... }:

{
  services.open-webui = {
    enable      = true;
    host        = "0.0.0.0";
    port        = 8888;
    openFirewall = true;

    environment = {
      OLLAMA_BASE_URL = "http://127.0.0.1:11500";
      WEBUI_AUTH      = "False";

      # Use ollama for embeddings — keeps RAG fully local
      RAG_EMBEDDING_ENGINE = "ollama";
      RAG_OLLAMA_BASE_URL  = "http://127.0.0.1:11500";
      RAG_EMBEDDING_MODEL  = "nomic-embed-text";

      CHUNK_SIZE    = "1500";
      CHUNK_OVERLAP = "200";
    };
  };
}
