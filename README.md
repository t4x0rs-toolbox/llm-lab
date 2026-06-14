# llm-lab

Local LLM lab on NixOS. Ollama + Open WebUI, CUDA-accelerated, models stored on a secondary NTFS disk.

**Stack:** NixOS 25.05 · Ollama (CUDA) · Open WebUI · gemma4:12b · nomic-embed-text (RAG)

---

## Requirements

- NixOS 25.05+
- NVIDIA Ampere GPU (RTX 3000 series or newer), 12 GB VRAM recommended
- Secondary disk for model storage (NTFS, ~50 GB free) — referred to as `discoD`
- Internet connection for the initial model download (~8 GB)

---

## Fresh install — one command

```bash
git clone https://github.com/t4x0rs-toolbox/llm-lab
cd llm-lab
sudo bash bootstrap.sh
```

The script will:
1. Add `home-manager` and `nixos-hardware` nix channels
2. Auto-detect your NTFS disk and ask you to confirm it's the right one
3. Copy all modules into `/etc/nixos/`
4. Patch your `configuration.nix` (adds the import + disk mount)
5. Run `nixos-rebuild switch`
6. Set up home-manager shell config for your user
7. Pull `nomic-embed-text` (RAG embeddings) + `gemma4:12b` and create the `gemma` persona

If your discoD UUID is known:
```bash
sudo bash bootstrap.sh 906AB8C26AB8A67E
```

---

## Prerequisites — NVIDIA drivers

The bootstrap does **not** touch your GPU config. Add this to your `configuration.nix` before running bootstrap (or after, then rebuild again):

```nix
imports = [
  <nixos-hardware/common/gpu/nvidia/ampere>
];

services.xserver.videoDrivers = [ "nvidia" ];
hardware.graphics.enable      = true;
hardware.graphics.enable32Bit = true;
hardware.nvidia.open               = true;
hardware.nvidia.modesetting.enable = true;
hardware.nvidia.nvidiaSettings     = true;
```

---

## After install

| What | Where |
|---|---|
| Open WebUI | http://localhost:8888 |
| Ollama API | http://127.0.0.1:11500 |
| Models dir | /mnt/discoD/ollamaModels |

Shell aliases (available after opening a new terminal):

```
llm-assist   # gemma4:12b — general assistant
llm-sec      # offsec persona (pull qwen2.5-coder:14b first)
llm-analyst  # analyst persona (pull phi4:14b first)
llm-rp       # roleplay persona (pull mistral-nemo:12b first)
gpu          # nvtop
vram         # VRAM usage snapshot
```

---

## Pulling extra models

```bash
OLLAMA_HOST=http://127.0.0.1:11500 ollama pull qwen2.5-coder:14b
OLLAMA_HOST=http://127.0.0.1:11500 ollama pull phi4:14b
OLLAMA_HOST=http://127.0.0.1:11500 ollama pull mistral-nemo:12b

# Create personas after pulling
ollama create offsec   -f /etc/nixos/modelfiles/offsec.Modelfile
ollama create analyst  -f /etc/nixos/modelfiles/phi4.Modelfile
ollama create roleplay -f /etc/nixos/modelfiles/roleplay.Modelfile
```

---

## Local file access (RAG)

Open WebUI has a built-in knowledge base. To chat with your documents:

1. **Workspace → Knowledge → New Collection**
2. Upload PDFs, text files, markdown, etc.
3. In any chat, click `+` → select the collection

Embeddings run locally via `nomic-embed-text` through Ollama — nothing leaves the machine.

---

## Updating config

Edit files in this repo, then redeploy:

```bash
# On Kali VM
bash deploy.sh

# On NixOS (command printed by deploy.sh)
bash <(curl -fsSL http://<KALI_IP>:9876/scripts/install.sh) <KALI_IP>
```

Or manually copy changed files to `/etc/nixos/` and run `sudo nixos-rebuild switch`.

---

## File map

```
bootstrap.sh                  ← run this on fresh NixOS
modules/
  llm-lab.nix                 ← top-level import (nvidia + ollama + open-webui)
  nvidia.nix                  ← CUDA package overrides
  ollama.nix                  ← Ollama service config (port 11500, discoD storage)
  open-webui.nix              ← Open WebUI (port 8888, local RAG)
modelfiles/
  gemma4.Modelfile            ← general assistant persona
  offsec.Modelfile            ← offensive security persona
  phi4.Modelfile              ← analyst persona
  roleplay.Modelfile          ← roleplay persona
home-manager/
  terminal.nix                ← zsh + starship + LLM aliases
scripts/
  setup-models.sh             ← pull base models + create personas
  start.sh                    ← manual service start (if not using systemd)
  install.sh                  ← used by deploy.sh (Kali → NixOS push)
deploy.sh                     ← run on Kali VM to push config changes
```
