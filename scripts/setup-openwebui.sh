#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-openwebui.sh — configures Open WebUI after nixos-rebuild.
# Run on the NixOS machine once Open WebUI is up.
#
# Usage:
#   bash setup-openwebui.sh <KALI_IP> [WEBUI_PORT] [ADMIN_EMAIL] [ADMIN_PASS]
#
# What it does:
#   1. Waits for Open WebUI to be accessible
#   2. Gets (or creates) an admin token
#   3. Deploys the URL Fetcher Filter
#   4. Sets the Kali proxy URL valve
#   5. Creates (or updates) the qwen3-sec workspace model
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

KALI_IP="${1:?ERROR: Kali IP required. Usage: bash setup-openwebui.sh <KALI_IP>}"
WEBUI_PORT="${2:-8888}"
ADMIN_EMAIL="${3:-admin@localhost}"
ADMIN_PASS="${4:-admin}"

WEBUI_URL="http://127.0.0.1:${WEBUI_PORT}"
KALI_PROXY_URL="http://${KALI_IP}:9879/fetch"
FILTER_ID="url_fetcher_filter"
MODEL_ID="qwen3-sec"

FILTER_FILE="/etc/nixos/openwebui/url-fetcher-filter.py"
NIXOS_DIR="/etc/nixos"

# ── Colors ────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1m'; N='\033[0m'

ok()   { echo -e "${G}  ✓${N}  $*"; }
err()  { echo -e "${R}  ✗${N}  $*" >&2; }
info() { echo -e "${C}  →${N}  $*"; }
warn() { echo -e "${Y}  !${N}  $*"; }

echo ""
echo -e "${B}┌─────────────────────────────────────────────┐${N}"
echo -e "${B}│  Open WebUI — post-install configuration    │${N}"
echo -e "${B}└─────────────────────────────────────────────┘${N}"
echo ""
info "WebUI URL     : $WEBUI_URL"
info "Kali proxy    : $KALI_PROXY_URL"
info "Admin email   : $ADMIN_EMAIL"
echo ""

# ── 1. Wait for Open WebUI ────────────────────────────────────────────────────
info "Waiting for Open WebUI to be accessible..."
MAX_WAIT=120
ELAPSED=0
until curl -sf --connect-timeout 3 "${WEBUI_URL}/api/version" >/dev/null 2>&1; do
    if [[ $ELAPSED -ge $MAX_WAIT ]]; then
        err "Open WebUI did not come up after ${MAX_WAIT}s."
        err "Check: journalctl -u open-webui -n 50"
        exit 1
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done
ok "Open WebUI is up"

# ── 2. Get admin token ────────────────────────────────────────────────────────
info "Authenticating..."

TOKEN=$(curl -sf -X POST "${WEBUI_URL}/api/v1/auths/signin" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASS}\"}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null || true)

if [[ -z "$TOKEN" ]]; then
    info "No existing user — creating admin account..."
    TOKEN=$(curl -sf -X POST "${WEBUI_URL}/api/v1/auths/signup" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"Admin\",\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASS}\"}" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null || true)
fi

if [[ -z "$TOKEN" ]]; then
    err "Could not obtain admin token. Open WebUI may still be initializing."
    err "Try running this script again in 30 seconds."
    exit 1
fi
ok "Authenticated (token obtained)"

AUTH_HEADER="Authorization: Bearer ${TOKEN}"

# ── 3. Deploy URL Fetcher Filter ──────────────────────────────────────────────
info "Deploying URL Fetcher Filter..."

if [[ ! -f "$FILTER_FILE" ]]; then
    err "Filter file not found: $FILTER_FILE"
    err "Re-run install.sh or copy openwebui/url-fetcher-filter.py to /etc/nixos/openwebui/"
    exit 1
fi

FILTER_CODE=$(cat "$FILTER_FILE")

FILTER_PAYLOAD=$(python3 -c "
import json, sys
code = open('$FILTER_FILE').read()
payload = {
    'id': '$FILTER_ID',
    'name': 'URL Fetcher Filter',
    'content': code,
    'meta': {
        'description': 'Fetches live URLs (JS-rendered) via Kali Chromium 131 proxy with playwright fallback',
        'manifest': {'title': 'URL Fetcher Filter', 'author': 'local', 'version': '10.0.0'}
    }
}
print(json.dumps(payload))
")

# Try update first (idempotent), fall back to create
UPDATE_RESULT=$(curl -s -X POST "${WEBUI_URL}/api/v1/functions/id/${FILTER_ID}/update" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "$FILTER_PAYLOAD" 2>/dev/null)

DEPLOYED_VER=$(echo "$UPDATE_RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('meta',{}).get('manifest',{}).get('version',''))
" 2>/dev/null || true)

if [[ -z "$DEPLOYED_VER" ]]; then
    info "Filter not found — creating it..."
    CREATE_RESULT=$(curl -s -X POST "${WEBUI_URL}/api/v1/functions/create" \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "$FILTER_PAYLOAD" 2>/dev/null)
    DEPLOYED_VER=$(echo "$CREATE_RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('meta',{}).get('manifest',{}).get('version','unknown'))
" 2>/dev/null || true)
fi

if [[ -n "$DEPLOYED_VER" ]]; then
    ok "URL Fetcher Filter deployed (v${DEPLOYED_VER})"
else
    warn "Filter deploy may have failed — check Open WebUI admin/functions"
fi

# ── 4. Set Kali proxy URL valve ───────────────────────────────────────────────
info "Setting Kali proxy URL valve → $KALI_PROXY_URL"

VALVE_RESULT=$(curl -s -X POST "${WEBUI_URL}/api/v1/functions/id/${FILTER_ID}/valves/update" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "{\"kali_proxy_url\": \"${KALI_PROXY_URL}\"}" 2>/dev/null)

VALVE_SET=$(echo "$VALVE_RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('kali_proxy_url',''))
" 2>/dev/null || true)

if [[ "$VALVE_SET" == "$KALI_PROXY_URL" ]]; then
    ok "Valve set: kali_proxy_url = $KALI_PROXY_URL"
else
    warn "Valve may not have been set (OW may need restart). Set manually:"
    warn "  Admin → Functions → URL Fetcher Filter → edit valve → $KALI_PROXY_URL"
fi

# ── 5. Create / update qwen3-sec workspace model ──────────────────────────────
info "Configuring qwen3-sec workspace model..."

MODEL_PAYLOAD=$(python3 -c "
import json
payload = {
    'id': '$MODEL_ID',
    'name': 'qwen3-sec',
    'base_model_id': 'qwen3-sec:latest',
    'params': {},
    'meta': {
        'description': 'Offensive security + recon assistant — qwen3:14b with live web browsing',
        'filterIds': ['$FILTER_ID'],
        'capabilities': {
            'web_search': True,
            'file_context': True
        }
    }
}
print(json.dumps(payload))
")

# Try update first, then create
MODEL_RESULT=$(curl -s -X POST "${WEBUI_URL}/api/v1/models/model/update?id=${MODEL_ID}" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "$MODEL_PAYLOAD" 2>/dev/null)

MODEL_ID_CHECK=$(echo "$MODEL_RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('id',''))
" 2>/dev/null || true)

if [[ "$MODEL_ID_CHECK" != "$MODEL_ID" ]]; then
    info "Workspace model not found — creating it..."
    MODEL_RESULT=$(curl -s -X POST "${WEBUI_URL}/api/v1/models/create" \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "$MODEL_PAYLOAD" 2>/dev/null)
    MODEL_ID_CHECK=$(echo "$MODEL_RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('id',''))
" 2>/dev/null || true)
fi

if [[ "$MODEL_ID_CHECK" == "$MODEL_ID" ]]; then
    ok "Workspace model '$MODEL_ID' configured (filter: $FILTER_ID)"
else
    warn "Workspace model may not have been created. Check Open WebUI → Workspace → Models"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
ok "Open WebUI configuration complete."
echo ""
echo -e "  ${B}Usage:${N}"
echo -e "    1. Open ${C}http://localhost:${WEBUI_PORT}${N}"
echo -e "    2. Select model: ${C}qwen3-sec${N} (not qwen3-sec:latest)"
echo -e "    3. Paste any URL in your message — the filter fetches it live"
echo ""
echo -e "  ${B}Kali fetch-proxy must be running:${N}"
echo -e "    ${C}systemctl --user status llm-fetch-proxy${N}  (on Kali)"
echo ""
