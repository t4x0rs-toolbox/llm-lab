#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# start.sh — LLM Lab quick-start dashboard
# Run this on the NixOS machine any time you want to check or restart the lab.
#
# Services are NixOS-managed systemd units — they survive reboots automatically.
# This script just ensures they're up and gives you the status at a glance.
# ─────────────────────────────────────────────────────────────────────────────

OLLAMA_PORT=11500
WEBUI_PORT=8888

# ── Colors ────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1m'; N='\033[0m'

# ── Header ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${B}╔══════════════════════════════════════════════════╗${N}"
echo -e "${B}║                 LLM Lab — Status                 ║${N}"
echo -e "${B}╚══════════════════════════════════════════════════╝${N}"
echo ""

# ── Service check/start ───────────────────────────────────────────────────────
check_or_start() {
    local svc="$1"
    local label="$2"
    if systemctl is-active --quiet "$svc"; then
        echo -e "  ${G}●${N}  ${label} (running)"
    else
        echo -e "  ${R}○${N}  ${label} (stopped) — starting..."
        sudo systemctl start "$svc"
        sleep 2
        if systemctl is-active --quiet "$svc"; then
            echo -e "  ${G}●${N}  ${label} (now running)"
        else
            echo -e "  ${R}✗${N}  ${label} failed to start"
            echo -e "      Check: ${C}journalctl -u $svc -n 30${N}"
        fi
    fi
}

echo -e "${B}Services:${N}"
check_or_start ollama    "Ollama      (API  :${OLLAMA_PORT})"
check_or_start open-webui "Open WebUI  (HTTP :${WEBUI_PORT})"
echo ""

# ── GPU status ────────────────────────────────────────────────────────────────
echo -e "${B}GPU:${N}"
if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    VRAM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)
    VRAM_FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1)
    VRAM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
    echo -e "  ${G}●${N}  ${GPU_NAME}"
    echo -e "     VRAM: ${VRAM_USED} MB used / ${VRAM_FREE} MB free / ${VRAM_TOTAL} MB total"
else
    echo -e "  ${Y}!${N}  nvidia-smi not found — reboot may be needed for NVIDIA drivers"
fi
echo ""

# ── Loaded models ─────────────────────────────────────────────────────────────
echo -e "${B}Currently loaded in VRAM:${N}"
LOADED=$(OLLAMA_HOST="http://127.0.0.1:${OLLAMA_PORT}" ollama ps 2>/dev/null | tail -n +2)
if [[ -n "$LOADED" ]]; then
    echo "$LOADED" | while IFS= read -r line; do
        echo -e "  ${G}●${N}  $line"
    done
else
    echo -e "  ${C}–${N}  none  (a model loads on first chat, unloads after ${OLLAMA_KEEP_ALIVE:-300}s idle)"
fi
echo ""

# ── Available personas ────────────────────────────────────────────────────────
echo -e "${B}Personas (model dropdown in Open WebUI / shell aliases):${N}"
echo -e "  ${C}offsec${N}   / llm-sec     →  qwen2.5-coder:14b  exploit code, tool dev"
echo -e "  ${C}analyst${N}  / llm-analyst →  phi4:14b           CTF reasoning, kill chains"
echo -e "  ${C}roleplay${N} / llm-rp      →  mistral-nemo:12b   character RP, narrative"
echo -e "  ${C}gemma${N}    / llm-assist  →  gemma4:12b         general assistant + vision"
echo ""

# ── Access ────────────────────────────────────────────────────────────────────
echo -e "${B}Access:${N}"
echo -e "  Browser  →  ${C}http://localhost:${WEBUI_PORT}${N}"
echo -e "  API      →  ${C}http://localhost:${OLLAMA_PORT}${N}  (or from LAN: replace localhost with machine IP)"
echo -e "  GPU mon  →  ${C}nvtop${N}"
echo ""

# ── Quick model pull reminder ─────────────────────────────────────────────────
echo -e "${B}Manage models:${N}"
echo -e "  Pull missing  →  ${C}OLLAMA_HOST=http://127.0.0.1:${OLLAMA_PORT} ollama pull <model>${N}"
echo -e "  List all      →  ${C}OLLAMA_HOST=http://127.0.0.1:${OLLAMA_PORT} ollama list${N}"
echo -e "  Re-run setup  →  ${C}bash /etc/nixos/scripts/setup-models.sh${N}"
echo ""
