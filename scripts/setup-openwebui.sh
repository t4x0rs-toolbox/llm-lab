#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-openwebui.sh — configures Open WebUI after nixos-rebuild.
# Run on the NixOS machine once Open WebUI is up.
#
# Usage:
#   bash setup-openwebui.sh [WEBUI_PORT] [ADMIN_EMAIL] [ADMIN_PASS]
#
# What it does:
#   1. Waits for Open WebUI to be accessible
#   2. Gets (or creates) an admin token
#   3. Deploys the URL Fetcher Filter
#   4. Creates (or updates) the qwen3-sec workspace model with filter attached
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

WEBUI_PORT="${1:-8888}"
ADMIN_EMAIL="${2:-admin@localhost}"
ADMIN_PASS="${3:-admin}"

WEBUI_URL="http://127.0.0.1:${WEBUI_PORT}"
FILTER_ID="url_fetcher_filter"
MODEL_ID="qwen3-sec"
FILTER_FILE="/etc/nixos/openwebui/url-fetcher-filter.py"

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
info "WebUI URL  : $WEBUI_URL"
info "Admin      : $ADMIN_EMAIL"
echo ""

# ── 1. Wait for Open WebUI ────────────────────────────────────────────────────
info "Waiting for Open WebUI..."
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
    err "Retry: bash $0 $WEBUI_PORT $ADMIN_EMAIL $ADMIN_PASS"
    exit 1
fi
ok "Authenticated"

AUTH_HEADER="Authorization: Bearer ${TOKEN}"

# ── 3. Deploy URL Fetcher Filter ──────────────────────────────────────────────
info "Deploying URL Fetcher Filter..."

if [[ ! -f "$FILTER_FILE" ]]; then
    err "Filter file not found: $FILTER_FILE"
    err "Copy openwebui/url-fetcher-filter.py from the repo to /etc/nixos/openwebui/"
    exit 1
fi

FILTER_PAYLOAD=$(python3 -c "
import json
code = open('$FILTER_FILE').read()
ver = '11.0.0'
# parse version from file if present
for line in code.splitlines():
    if 'version:' in line:
        ver = line.split('version:')[-1].strip().strip('\"')
        break
payload = {
    'id': '$FILTER_ID',
    'name': 'URL Fetcher Filter',
    'content': code,
    'meta': {
        'description': 'Fetches live URLs (JS-rendered SPAs) using system Chromium — no external proxy needed',
        'manifest': {'title': 'URL Fetcher Filter', 'author': 'local', 'version': ver}
    }
}
print(json.dumps(payload))
")

# Try update first (idempotent on re-runs), fall back to create
UPDATE_RESULT=$(curl -s -X POST "${WEBUI_URL}/api/v1/functions/id/${FILTER_ID}/update" \
    -H "$AUTH_HEADER" -H "Content-Type: application/json" \
    -d "$FILTER_PAYLOAD" 2>/dev/null)

DEPLOYED_VER=$(echo "$UPDATE_RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('meta',{}).get('manifest',{}).get('version',''))
" 2>/dev/null || true)

if [[ -z "$DEPLOYED_VER" ]]; then
    info "Filter not found — creating..."
    CREATE_RESULT=$(curl -s -X POST "${WEBUI_URL}/api/v1/functions/create" \
        -H "$AUTH_HEADER" -H "Content-Type: application/json" \
        -d "$FILTER_PAYLOAD" 2>/dev/null)
    DEPLOYED_VER=$(echo "$CREATE_RESULT" | python3 -c "
import sys,json; d=json.load(sys.stdin)
print(d.get('meta',{}).get('manifest',{}).get('version','unknown'))
" 2>/dev/null || true)
fi

if [[ -n "$DEPLOYED_VER" ]]; then
    ok "URL Fetcher Filter v${DEPLOYED_VER} deployed"
else
    warn "Filter deploy may have failed — check Open WebUI admin/functions"
fi

# ── 4. Create / update qwen3-sec workspace model ──────────────────────────────
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
        'capabilities': {'web_search': True, 'file_context': True}
    }
}
print(json.dumps(payload))
")

MODEL_RESULT=$(curl -s -X POST "${WEBUI_URL}/api/v1/models/model/update?id=${MODEL_ID}" \
    -H "$AUTH_HEADER" -H "Content-Type: application/json" \
    -d "$MODEL_PAYLOAD" 2>/dev/null)

MODEL_OK=$(echo "$MODEL_RESULT" | python3 -c "
import sys,json; d=json.load(sys.stdin); print(d.get('id',''))
" 2>/dev/null || true)

if [[ "$MODEL_OK" != "$MODEL_ID" ]]; then
    info "Model not found — creating..."
    MODEL_RESULT=$(curl -s -X POST "${WEBUI_URL}/api/v1/models/create" \
        -H "$AUTH_HEADER" -H "Content-Type: application/json" \
        -d "$MODEL_PAYLOAD" 2>/dev/null)
    MODEL_OK=$(echo "$MODEL_RESULT" | python3 -c "
import sys,json; d=json.load(sys.stdin); print(d.get('id',''))
" 2>/dev/null || true)
fi

if [[ "$MODEL_OK" == "$MODEL_ID" ]]; then
    ok "Workspace model '$MODEL_ID' ready (filter: $FILTER_ID attached)"
else
    warn "Workspace model may not have been created. Check Workspace → Models in the UI"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
ok "Open WebUI configuration complete."
echo ""
echo -e "  ${B}Usage:${N}"
echo -e "    1. Open ${C}http://localhost:${WEBUI_PORT}${N}"
echo -e "    2. Select model: ${C}qwen3-sec${N}  (not qwen3-sec:latest)"
echo -e "    3. Paste any URL — the filter fetches it live via system Chromium"
echo ""
