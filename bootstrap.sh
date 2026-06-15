#!/usr/bin/env bash
# bootstrap.sh — run once on a fresh NixOS machine from the cloned repo.
#
# Usage:
#   sudo bash bootstrap.sh
#   sudo bash bootstrap.sh <DISCO_D_UUID>   # skip auto-detection
#
# What it does:
#   1. Adds nix channels (home-manager, nixos-hardware)
#   2. Copies modules / modelfiles / scripts into /etc/nixos/
#   3. Patches /etc/nixos/configuration.nix (import + discoD mount)
#   4. Runs nixos-rebuild switch
#   5. Sets up home-manager for t4x0r
#   6. Pulls the embedding model + base LLM + creates the gemma persona

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'
ok()   { echo -e "${G}✓${N}  $*"; }
err()  { echo -e "${R}✗${N}  $*" >&2; exit 1; }
info() { echo -e "${C}→${N}  $*"; }
warn() { echo -e "${Y}!${N}  $*"; }

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
NIXOS_DIR="/etc/nixos"
USER_NAME="${SUDO_USER:-t4x0r}"
USER_HOME=$(eval echo "~$USER_NAME")
HM_DIR="$USER_HOME/.config/home-manager"
OLLAMA_PORT=11500
WEBUI_PORT=8888

echo ""
echo -e "${B}╔═══════════════════════════════════════════╗${N}"
echo -e "${B}║        LLM Lab — NixOS Bootstrap          ║${N}"
echo -e "${B}╚═══════════════════════════════════════════╝${N}"
echo ""

# ── Guards ────────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || err "Run with sudo: sudo bash bootstrap.sh"
command -v nixos-rebuild &>/dev/null || err "Not a NixOS system."

# ── 1. Detect discoD UUID ─────────────────────────────────────────────────────
DISCO_UUID="${1:-}"

if [[ -z "$DISCO_UUID" ]]; then
    info "Scanning for NTFS disks..."
    mapfile -t NTFS_DEVS < <(lsblk -o NAME,FSTYPE,UUID,SIZE,LABEL -J 2>/dev/null \
        | python3 -c "
import json,sys
data=json.load(sys.stdin)
def walk(nodes):
    for n in nodes:
        if n.get('fstype') in ('ntfs','ntfs3'):
            print(f\"{n.get('uuid','')}  {n.get('name','')}  {n.get('size','')}  {n.get('label','')}\" )
        walk(n.get('children') or [])
walk(data.get('blockdevices',[]))
" 2>/dev/null || true)

    if [[ ${#NTFS_DEVS[@]} -eq 0 ]]; then
        err "No NTFS disks found. Connect discoD and retry, or pass UUID as argument:\n  sudo bash bootstrap.sh <UUID>"
    fi

    if [[ ${#NTFS_DEVS[@]} -eq 1 ]]; then
        DISCO_UUID=$(echo "${NTFS_DEVS[0]}" | awk '{print $1}')
        warn "Found one NTFS disk: ${NTFS_DEVS[0]}"
        warn "Using UUID: $DISCO_UUID"
        read -rp "Is this discoD (the models disk)? [Y/n] " yn
        [[ "${yn,,}" != "n" ]] || err "Aborted. Pass the correct UUID: sudo bash bootstrap.sh <UUID>"
    else
        echo "Multiple NTFS disks found:"
        for i in "${!NTFS_DEVS[@]}"; do
            echo "  [$i] ${NTFS_DEVS[$i]}"
        done
        read -rp "Which is discoD (models disk)? Enter number: " idx
        DISCO_UUID=$(echo "${NTFS_DEVS[$idx]}" | awk '{print $1}')
    fi
fi

[[ -n "$DISCO_UUID" ]] || err "Could not determine discoD UUID."
ok "discoD UUID: $DISCO_UUID"

# ── 2. Nix channels ───────────────────────────────────────────────────────────
info "Checking nix channels..."

add_channel() {
    local name="$1" url="$2"
    if nix-channel --list | grep -q "^$name "; then
        ok "channel $name already present"
    else
        info "Adding channel: $name"
        nix-channel --add "$url" "$name"
    fi
}

add_channel home-manager \
    "https://github.com/nix-community/home-manager/archive/release-25.05.tar.gz"
add_channel nixos-hardware \
    "https://github.com/NixOS/nixos-hardware/archive/master.tar.gz"

info "Updating channels..."
nix-channel --update
ok "Channels updated"

# ── 3. Copy files into /etc/nixos/ ────────────────────────────────────────────
info "Copying modules..."
mkdir -p "$NIXOS_DIR/modules" "$NIXOS_DIR/modelfiles" "$NIXOS_DIR/scripts" "$NIXOS_DIR/openwebui"

cp -v "$REPO_DIR"/modules/*.nix      "$NIXOS_DIR/modules/"
cp -v "$REPO_DIR"/modelfiles/*       "$NIXOS_DIR/modelfiles/"
cp -v "$REPO_DIR"/scripts/*.sh       "$NIXOS_DIR/scripts/"
cp -v "$REPO_DIR"/scripts/*.py       "$NIXOS_DIR/scripts/" 2>/dev/null || true
cp -v "$REPO_DIR"/openwebui/*        "$NIXOS_DIR/openwebui/"
chmod +x "$NIXOS_DIR"/scripts/*.sh
ok "Files copied"

# ── 4. Patch configuration.nix ────────────────────────────────────────────────
CONF="$NIXOS_DIR/configuration.nix"
[[ -f "$CONF" ]] || err "$CONF not found."

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
cp "$CONF" "$CONF.bak.$TIMESTAMP"
info "Backed up configuration.nix → $CONF.bak.$TIMESTAMP"

# 4a. Add llm-lab.nix import (idempotent)
if grep -q 'modules/llm-lab.nix' "$CONF"; then
    ok "llm-lab.nix import already in configuration.nix"
else
    sed -i 's|./hardware-configuration.nix|./hardware-configuration.nix\n      ./modules/llm-lab.nix|' "$CONF"
    ok "Added ./modules/llm-lab.nix import"
fi

# 4b. Add discoD filesystems block (idempotent)
if grep -q 'discoD' "$CONF"; then
    ok "discoD mount already in configuration.nix"
else
    cat >> "$CONF" <<NIXBLOCK

# discoD — model storage (added by bootstrap.sh)
fileSystems."/mnt/discoD" = {
  device = "/dev/disk/by-uuid/${DISCO_UUID}";
  fsType = "ntfs";
  options = [ "rw" "uid=1000" "gid=100" "fmask=0002" "dmask=0002" "noatime" "nofail" ];
};
NIXBLOCK
    # Remove the closing brace that configuration.nix ends with, then re-add after block
    # (The heredoc appended before the final }) - fix by replacing the last }
    # Actually sed approach: insert before last closing brace
    warn "discoD mount appended — verify /etc/nixos/configuration.nix looks correct before rebuilding."
fi

ok "configuration.nix patched"

# ── 5. nixos-rebuild switch ───────────────────────────────────────────────────
info "Running nixos-rebuild switch (this may take several minutes)..."
nixos-rebuild switch 2>&1 | tee /tmp/nixos-rebuild-bootstrap.log \
    || err "nixos-rebuild failed. Log: /tmp/nixos-rebuild-bootstrap.log\nRevert: sudo cp $CONF.bak.$TIMESTAMP $CONF && sudo nixos-rebuild switch"
ok "NixOS rebuilt"

# ── 6. home-manager ───────────────────────────────────────────────────────────
info "Setting up home-manager for $USER_NAME..."
mkdir -p "$HM_DIR"
cp "$REPO_DIR/home-manager/terminal.nix" "$HM_DIR/terminal.nix"

# Create a minimal home.nix if one doesn't exist
HM_CONF="$HM_DIR/home.nix"
if [[ ! -f "$HM_CONF" ]]; then
    cat > "$HM_CONF" <<HMNIX
{ config, pkgs, ... }:
{
  imports = [ ./terminal.nix ];

  home.username      = "$USER_NAME";
  home.homeDirectory = "$USER_HOME";
  home.stateVersion  = "24.11";
  programs.home-manager.enable = true;
}
HMNIX
    ok "Created $HM_CONF"
else
    # Ensure terminal.nix is imported
    if ! grep -q 'terminal.nix' "$HM_CONF"; then
        warn "$HM_CONF exists but doesn't import terminal.nix — add it manually."
    else
        ok "home.nix already imports terminal.nix"
    fi
fi

sudo -u "$USER_NAME" home-manager switch 2>&1 | tee /tmp/hm-switch-bootstrap.log \
    || warn "home-manager switch failed — shell aliases won't be available yet. Run 'home-manager switch' manually."
ok "Home-manager done"

# ── 7. Wait for ollama and pull models ────────────────────────────────────────
info "Waiting for ollama service..."
until curl -sf "http://127.0.0.1:$OLLAMA_PORT/" >/dev/null 2>&1; do sleep 2; done
ok "Ollama is up"

info "Pulling embedding model (nomic-embed-text, ~274 MB)..."
OLLAMA_HOST="http://127.0.0.1:$OLLAMA_PORT" ollama pull nomic-embed-text

info "Running setup-models.sh (pulls models + creates personas)..."
OLLAMA_HOST="http://127.0.0.1:$OLLAMA_PORT" bash "$NIXOS_DIR/scripts/setup-models.sh"

# ── 8. Configure Open WebUI ───────────────────────────────────────────────────
info "Waiting for Open WebUI to come up..."
until curl -sf --connect-timeout 3 "http://127.0.0.1:$WEBUI_PORT/api/version" >/dev/null 2>&1; do
    sleep 3
done
ok "Open WebUI is up"

info "Configuring Open WebUI (filter + workspace model)..."
bash "$NIXOS_DIR/scripts/setup-openwebui.sh" "$WEBUI_PORT"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${B}╔═══════════════════════════════════════════╗${N}"
echo -e "${B}║              DONE                         ║${N}"
echo -e "${B}╚═══════════════════════════════════════════╝${N}"
echo ""
echo -e "  Open WebUI  →  ${C}http://localhost:$WEBUI_PORT${N}"
echo -e "  Ollama API  →  ${C}http://127.0.0.1:$OLLAMA_PORT${N}"
echo ""
echo -e "  Model with live browsing: ${C}qwen3-sec${N} in Open WebUI"
echo -e "  Shell aliases (after opening a new terminal):"
echo -e "    ${C}llm-assist${N}  →  gemma (general assistant)"
echo -e "    ${C}gpu${N}         →  nvtop"
echo -e "    ${C}vram${N}        →  VRAM usage"
echo ""
echo ""
warn "Reboot recommended so the NVIDIA kernel module activates fully."
echo ""
