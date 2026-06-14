#!/usr/bin/env bash
# Run this on the NixOS machine AFTER nixos-rebuild switch.
# Pulls all base models and creates the custom personas.
# Requires: ollama service running (systemctl status ollama)

set -euo pipefail

MODELFILES_DIR="$(cd "$(dirname "$0")/../modelfiles" && pwd)"

wait_for_ollama() {
    echo "Waiting for Ollama to be ready..."
    until curl -sf http://127.0.0.1:11500/ >/dev/null 2>&1; do
        sleep 2
    done
    echo "Ollama is up."
}

wait_for_ollama

echo ""
echo "=== Pulling base model ==="

echo "gemma4:12b         (~7.6 GB) — assistant | Gemma ToS  | general knowledge + vision"
ollama pull gemma4:12b

echo ""
echo "=== Creating custom model persona ==="
ollama create gemma     -f "$MODELFILES_DIR/gemma4.Modelfile"

echo ""
echo "=== Done. Installed models: ==="
ollama list

echo ""
echo "Open WebUI: http://localhost:8888"
echo "Ollama API: http://localhost:11500"
echo ""
echo "Personas available in Open WebUI:"
echo "  gemma    — general assistant, research, documentation (gemma4:12b)"
echo ""
echo "To add remaining models later, run:"
echo "  OLLAMA_HOST=http://127.0.0.1:11500 ollama pull qwen2.5-coder:14b"
echo "  OLLAMA_HOST=http://127.0.0.1:11500 ollama pull mistral-nemo:12b"
echo "  OLLAMA_HOST=http://127.0.0.1:11500 ollama pull phi4:14b"
