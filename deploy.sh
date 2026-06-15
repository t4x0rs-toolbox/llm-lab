#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh — runs on the KALI VM
#
# Serves the nixosconfig directory over HTTP so the NixOS machine can pull it,
# then prints the one-liner to run on the NixOS machine.
#
# Usage:
#   bash deploy.sh [NIXOS_IP]         (default: 192.168.1.102)
#
# What happens:
#   1. Starts a temporary HTTP server on this VM (port 9876)
#   2. Prints the bootstrap command to run on the NixOS machine
#   3. Waits. Ctrl+C stops the server.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

NIXOS_IP="${1:-192.168.1.102}"
SERVE_PORT=9876
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colors ────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1m'; N='\033[0m'

ok()   { echo -e "${G}✓${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*" >&2; }
info() { echo -e "${C}→${N}  $*"; }
warn() { echo -e "${Y}!${N}  $*"; }

# ── Sanity checks ─────────────────────────────────────────────────────────────
echo ""
echo -e "${B}╔════════════════════════════════════════════╗${N}"
echo -e "${B}║        LLM Lab — Kali Deploy Server        ║${N}"
echo -e "${B}╚════════════════════════════════════════════╝${N}"
echo ""

if [[ ! -f "$SCRIPT_DIR/scripts/install.sh" ]]; then
    err "scripts/install.sh not found. Run from the nixosconfig directory."
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    err "python3 required to serve files."
    exit 1
fi

# ── Detect Kali's LAN IP (the one reachable from NixOS) ──────────────────────
KALI_IP=$(ip route get "$NIXOS_IP" 2>/dev/null \
    | grep -oP 'src \K[^ ]+' | head -1 || true)

if [[ -z "$KALI_IP" ]]; then
    KALI_IP=$(hostname -I | awk '{print $1}')
    warn "Could not auto-detect LAN IP via route, using: $KALI_IP"
    warn "If wrong, edit KALI_IP manually in this script."
fi

ok "Kali IP  : $KALI_IP"
ok "NixOS IP : $NIXOS_IP"
ok "Serve dir: $SCRIPT_DIR"
ok "Port     : $SERVE_PORT"

# ── Firewall: open serve port temporarily if nftables active ─────────────────
if command -v nft &>/dev/null 2>&1; then
    sudo nft add rule inet filter input tcp dport "$SERVE_PORT" accept 2>/dev/null \
        && info "Port $SERVE_PORT opened in nftables" \
        || true
fi

# ── Start HTTP server ─────────────────────────────────────────────────────────
info "Starting HTTP server..."
cd "$SCRIPT_DIR"
python3 -m http.server "$SERVE_PORT" --bind 0.0.0.0 &>/tmp/llm-deploy-http.log &
HTTP_PID=$!

sleep 1
if ! kill -0 "$HTTP_PID" 2>/dev/null; then
    err "HTTP server failed to start. Check /tmp/llm-deploy-http.log"
    exit 1
fi
ok "HTTP server running (PID $HTTP_PID)"

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    echo ""
    info "Stopping HTTP server..."
    kill "$HTTP_PID" 2>/dev/null || true
    ok "Done."
}
trap cleanup EXIT INT TERM

# ── Print the command to run on NixOS ────────────────────────────────────────
echo ""
echo -e "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${B}  Run this on the NixOS machine:${N}"
echo ""
echo -e "  ${C}bash <(curl -fsSL http://$KALI_IP:$SERVE_PORT/scripts/install.sh) $KALI_IP $SERVE_PORT${N}"
echo ""
echo -e "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""
warn "Keep this terminal open until the NixOS install finishes."
warn "Ctrl+C to stop the server when done."
echo ""

# ── Wait ──────────────────────────────────────────────────────────────────────
wait "$HTTP_PID" 2>/dev/null || true
