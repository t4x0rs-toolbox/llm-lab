#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# install.sh — runs on the NIXOS machine
#
# Usage (printed by deploy.sh on Kali):
#   bash <(curl -fsSL http://<KALI_IP>:9876/scripts/install.sh) <KALI_IP> [PORT]
#
# What it does:
#   1. Backs up /etc/nixos/ and ~/.config/home-manager/
#   2. Downloads all config files from the Kali VM
#   3. Installs NixOS modules under /etc/nixos/modules/
#   4. Patches configuration.nix (import + firewall ports 11500 & 8888)
#   5. Replaces ~/.config/home-manager/terminal.nix
#   6. Runs nixos-rebuild switch
#   7. Runs home-manager switch
#   8. Pulls all four models (~34 GB to /mnt/discoD/ollamaModels)
#
# Ports used:
#   Ollama API : 11500  (default was 11434)
#   Open WebUI : 8888   (default was 3000)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

KALI_IP="${1:?ERROR: Kali IP required. Usage: bash install.sh <KALI_IP> [PORT]}"
KALI_PORT="${2:-9876}"
BASE_URL="http://${KALI_IP}:${KALI_PORT}"

OLLAMA_PORT=11500
WEBUI_PORT=8888

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${HOME}/backups/llm-lab-pre-${TIMESTAMP}"
NIXOS_DIR="/etc/nixos"
HM_DIR="${HOME}/.config/home-manager"
MODULES_DEST="${NIXOS_DIR}/modules"
MODELFILES_DEST="${NIXOS_DIR}/modelfiles"
SCRIPTS_DEST="${NIXOS_DIR}/scripts"

# ── Colors ────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1m'; N='\033[0m'

ok()     { echo -e "${G}  ✓${N}  $*"; }
err()    { echo -e "${R}  ✗${N}  $*" >&2; }
info()   { echo -e "${C}  →${N}  $*"; }
warn()   { echo -e "${Y}  !${N}  $*"; }
banner() {
    echo ""
    echo -e "${B}┌─────────────────────────────────────────────┐${N}"
    echo -e "${B}│  $*$(printf '%*s' $((43 - ${#1})) '')│${N}"
    echo -e "${B}└─────────────────────────────────────────────┘${N}"
}

# ── Guards ────────────────────────────────────────────────────────────────────
if ! command -v nixos-rebuild &>/dev/null; then
    err "nixos-rebuild not found. This script must run on a NixOS system."
    exit 1
fi

if ! command -v home-manager &>/dev/null; then
    err "home-manager not found. Install it first:  nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager && nix-channel --update"
    exit 1
fi


echo ""
echo -e "${B}╔══════════════════════════════════════════════════╗${N}"
echo -e "${B}║           LLM Lab — NixOS Installer              ║${N}"
echo -e "${B}║                                                  ║${N}"
echo -e "${B}║  Ollama API : port ${OLLAMA_PORT}                         ║${N}"
echo -e "${B}║  Open WebUI : port ${WEBUI_PORT}                          ║${N}"
echo -e "${B}╚══════════════════════════════════════════════════╝${N}"

# ── Phase 1: Backup ───────────────────────────────────────────────────────────
banner "PHASE 1 — Backup"

mkdir -p "${BACKUP_DIR}"

info "Backing up /etc/nixos/ ..."
sudo cp -r "${NIXOS_DIR}" "${BACKUP_DIR}/nixos"
ok "/etc/nixos/ → ${BACKUP_DIR}/nixos"

if [[ -d "${HM_DIR}" ]]; then
    info "Backing up ~/.config/home-manager/ ..."
    cp -r "${HM_DIR}" "${BACKUP_DIR}/home-manager"
    ok "~/.config/home-manager/ → ${BACKUP_DIR}/home-manager"
else
    warn "No home-manager config found at ${HM_DIR} — skipping that backup."
fi

ok "Backup complete: ${BACKUP_DIR}"
warn "To revert:  sudo cp -r ${BACKUP_DIR}/nixos/* /etc/nixos/ && sudo nixos-rebuild switch"

# ── Phase 2: Check connectivity to Kali ──────────────────────────────────────
banner "PHASE 2 — Connecting to Kali file server"

info "Testing ${BASE_URL} ..."
if ! curl -sf --connect-timeout 5 "${BASE_URL}/" > /dev/null; then
    err "Cannot reach ${BASE_URL}"
    err "Make sure deploy.sh is running on the Kali VM."
    exit 1
fi
ok "Connected to Kali at ${BASE_URL}"

# ── Phase 3: Download NixOS modules ──────────────────────────────────────────
banner "PHASE 3 — Downloading NixOS modules"

sudo mkdir -p "${MODULES_DEST}" "${MODELFILES_DEST}" "${SCRIPTS_DEST}"

NixOS_MODULES=(nvidia.nix ollama.nix open-webui.nix llm-lab.nix playwright.nix)
for f in "${NixOS_MODULES[@]}"; do
    info "modules/${f}"
    curl -sf "${BASE_URL}/modules/${f}" | sudo tee "${MODULES_DEST}/${f}" > /dev/null
    ok "  → ${MODULES_DEST}/${f}"
done

MODELFILES=(offsec.Modelfile roleplay.Modelfile phi4.Modelfile gemma4.Modelfile qwen3.Modelfile)
for f in "${MODELFILES[@]}"; do
    info "modelfiles/${f}"
    curl -sf "${BASE_URL}/modelfiles/${f}" | sudo tee "${MODELFILES_DEST}/${f}" > /dev/null
    ok "  → ${MODELFILES_DEST}/${f}"
done

SCRIPTS=(setup-models.sh setup-openwebui.sh start.sh)
for f in "${SCRIPTS[@]}"; do
    info "scripts/${f}"
    curl -sf "${BASE_URL}/scripts/${f}" | sudo tee "${SCRIPTS_DEST}/${f}" > /dev/null
    sudo chmod +x "${SCRIPTS_DEST}/${f}"
    ok "  → ${SCRIPTS_DEST}/${f}"
done

# Open WebUI filter and model definitions
OPENWEBUI_DEST="${NIXOS_DIR}/openwebui"
sudo mkdir -p "${OPENWEBUI_DEST}"
OPENWEBUI_FILES=(url-fetcher-filter.py)
for f in "${OPENWEBUI_FILES[@]}"; do
    info "openwebui/${f}"
    curl -sf "${BASE_URL}/openwebui/${f}" | sudo tee "${OPENWEBUI_DEST}/${f}" > /dev/null
    ok "  → ${OPENWEBUI_DEST}/${f}"
done

# ── Phase 4: Patch /etc/nixos/configuration.nix ──────────────────────────────
banner "PHASE 4 — Patching configuration.nix"

if [[ ! -f "${NIXOS_DIR}/configuration.nix" ]]; then
    err "${NIXOS_DIR}/configuration.nix not found."
    exit 1
fi

CONF="${NIXOS_DIR}/configuration.nix"

# 1) Add ./modules/llm-lab.nix to imports (idempotent)
if grep -q './modules/llm-lab.nix' "$CONF"; then
    info "llm-lab.nix import already present"
else
    sudo sed -i 's|./hardware-configuration.nix|./hardware-configuration.nix\n      ./modules/llm-lab.nix|' "$CONF"
    ok "added ./modules/llm-lab.nix to imports"
fi

# 2) Add firewall ports (idempotent)
if grep -q "${OLLAMA_PORT}" "$CONF"; then
    info "firewall ports already present"
else
    sudo sed -i "s/allowedTCPPorts\s*=\s*\[/allowedTCPPorts = [ ${OLLAMA_PORT} ${WEBUI_PORT} /" "$CONF"
    ok "added firewall ports ${OLLAMA_PORT} ${WEBUI_PORT}"
fi

ok "configuration.nix patched"

# ── Phase 5: Replace home-manager terminal.nix ───────────────────────────────
banner "PHASE 5 — Updating home-manager terminal.nix"

if [[ ! -d "${HM_DIR}" ]]; then
    warn "Creating ${HM_DIR} — make sure your home.nix imports ./terminal.nix"
    mkdir -p "${HM_DIR}"
fi

info "Downloading home-manager/terminal.nix ..."
curl -sf "${BASE_URL}/home-manager/terminal.nix" > "${HM_DIR}/terminal.nix"
ok "${HM_DIR}/terminal.nix updated"

# ── Phase 6: NixOS rebuild ────────────────────────────────────────────────────
banner "PHASE 6 — nixos-rebuild switch"
warn "This downloads and builds NVIDIA drivers + services. May take several minutes."
echo ""

if ! sudo nixos-rebuild switch 2>&1 | tee /tmp/nixos-rebuild-"${TIMESTAMP}".log; then
    err "nixos-rebuild failed. Log: /tmp/nixos-rebuild-${TIMESTAMP}.log"
    err "To revert:  sudo cp -r ${BACKUP_DIR}/nixos /etc/nixos && sudo nixos-rebuild switch"
    exit 1
fi

ok "NixOS rebuilt successfully"

# ── Phase 7: home-manager switch ─────────────────────────────────────────────
banner "PHASE 7 — home-manager switch"

if ! home-manager switch 2>&1 | tee /tmp/hm-switch-"${TIMESTAMP}".log; then
    err "home-manager switch failed. Log: /tmp/hm-switch-${TIMESTAMP}.log"
    warn "NixOS rebuild was fine — only shell config is affected. You can retry:"
    warn "  home-manager switch"
    # Don't exit — the system is usable even if hm fails
fi

ok "Home Manager updated"

# ── Phase 8: Pull models ──────────────────────────────────────────────────────
banner "PHASE 8 — Models"
info "Waiting for Ollama to be ready..."
until curl -sf "http://127.0.0.1:${OLLAMA_PORT}/" >/dev/null 2>&1; do sleep 3; done
ok "Ollama is up"

info "Pulling nomic-embed-text (~274 MB) — required for RAG..."
OLLAMA_HOST="http://127.0.0.1:${OLLAMA_PORT}" ollama pull nomic-embed-text
ok "nomic-embed-text ready"

info "Running setup-models.sh (pulls base models + creates personas)..."
OLLAMA_HOST="http://127.0.0.1:${OLLAMA_PORT}" bash "${SCRIPTS_DEST}/setup-models.sh"

# ── Phase 9: Configure Open WebUI ────────────────────────────────────────────
banner "PHASE 9 — Open WebUI configuration"
info "Deploying URL Fetcher Filter and qwen3-sec workspace model..."

info "Waiting for Open WebUI to be ready..."
until curl -sf --connect-timeout 3 "http://127.0.0.1:${WEBUI_PORT}/api/version" >/dev/null 2>&1; do
    sleep 3
done
ok "Open WebUI is up"

bash "${SCRIPTS_DEST}/setup-openwebui.sh" "${KALI_IP}" "${WEBUI_PORT}"

# ── Done ──────────────────────────────────────────────────────────────────────
banner "INSTALLATION COMPLETE"
echo ""
echo -e "  ${B}Open WebUI${N}   →  ${C}http://localhost:${WEBUI_PORT}${N}"
echo -e "  ${B}Ollama API${N}   →  ${C}http://localhost:${OLLAMA_PORT}${N}"
echo ""
echo -e "  ${B}Web UI:${N}  ${C}http://localhost:${WEBUI_PORT}${N}"
echo -e "  ${B}Model:${N}   select ${C}qwen3-sec${N} for live browsing + offsec persona"
echo ""
echo -e "  ${B}Quick start (after reboot):${N}"
echo -e "    ${C}bash ${SCRIPTS_DEST}/start.sh${N}"
echo ""
echo -e "  ${B}Fetch proxy (must run on Kali):${N}"
echo -e "    ${C}systemctl --user status llm-fetch-proxy${N}"
echo ""
warn "Reboot recommended — NVIDIA kernel module needs it to become active."
warn "After reboot, CUDA acceleration will kick in automatically."
echo ""
