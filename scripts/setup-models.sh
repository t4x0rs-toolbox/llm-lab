#!/usr/bin/env bash
# Run this on the NixOS machine AFTER nixos-rebuild switch.
# Pulls all base models and creates the custom personas.
# Requires: ollama service running (systemctl status ollama)

set -euo pipefail

OLLAMA_PORT=11500
MODELFILES_DIR="$(cd "$(dirname "$0")/../modelfiles" && pwd)"

wait_for_ollama() {
    echo "Waiting for Ollama to be ready..."
    until curl -sf "http://127.0.0.1:${OLLAMA_PORT}/" >/dev/null 2>&1; do
        sleep 2
    done
    echo "Ollama is up."
}

wait_for_ollama

echo ""
echo "=== Pulling base models ==="

echo "gemma4:12b   (~7.6 GB) — general assistant + vision"
ollama pull gemma4:12b

echo "qwen3:14b    (~9.3 GB) — offensive security + web research"
ollama pull qwen3:14b

echo "nomic-embed-text (~274 MB) — RAG embeddings"
ollama pull nomic-embed-text

echo ""
echo "=== Creating custom model personas ==="

ollama create gemma     -f "$MODELFILES_DIR/gemma4.Modelfile"
echo "  ✓ gemma (gemma4:12b + persona)"

ollama create qwen3-sec -f "$MODELFILES_DIR/qwen3.Modelfile"
echo "  ✓ qwen3-sec (qwen3:14b + offsec persona)"

echo ""
echo "=== Done. Installed models: ==="
ollama list

echo ""
echo "Open WebUI : http://localhost:8888"
echo "Ollama API : http://localhost:${OLLAMA_PORT}"
echo ""
echo "Personas:"
echo "  gemma     — general assistant, research, vision (gemma4:12b)"
echo "  qwen3-sec — offsec + live web browsing (qwen3:14b)"
echo "              → use the 'qwen3-sec' workspace model in Open WebUI for URL fetching"
echo ""
echo "Optional models (pull separately):"
echo "  OLLAMA_HOST=http://127.0.0.1:${OLLAMA_PORT} ollama pull phi4:14b"
echo "  OLLAMA_HOST=http://127.0.0.1:${OLLAMA_PORT} ollama pull mistral-nemo:12b"
