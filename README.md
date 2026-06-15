# llm-lab

Local LLM lab on NixOS. Ollama + Open WebUI, CUDA-accelerated, models stored on a secondary NTFS disk.

**Stack:** NixOS 25.05 · Ollama (CUDA) · Open WebUI · qwen3:14b · gemma4:12b · nomic-embed-text (RAG)

---

## Features

- **`qwen3-sec`** — offensive security assistant (qwen3:14b) with **live web browsing**: paste any URL and the model fetches the page, including JS-rendered SPAs (React/Vue), and answers from the live content
- **`gemma`** — general assistant (gemma4:12b)
- Local RAG via `nomic-embed-text` — upload docs, chat with them, nothing leaves the machine
- DuckDuckGo web search built in

---

## Requirements

- NixOS 25.05+
- NVIDIA Ampere GPU (RTX 3000 series or newer), 12 GB VRAM recommended
- Secondary disk for model storage (NTFS, ~50 GB free) — referred to as `discoD`
- Internet connection for the initial model download (~35 GB total for both models)

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
7. Pull `nomic-embed-text` + `gemma4:12b` + `qwen3:14b` and create personas
8. Configure Open WebUI: deploy the URL Fetcher Filter and create the `qwen3-sec` workspace model

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
gpu          # nvtop
vram         # VRAM usage snapshot
```

---

## Live web browsing (qwen3-sec)

Select **`qwen3-sec`** in Open WebUI and paste any URL in your message. The URL Fetcher Filter intercepts the request, launches Chromium headlessly, waits for the page to fully render, and injects the live content into the model's context before it replies.

Works on JS-heavy SPAs — React, Vue, etc. — not just static HTML.

**Example:**
```
fetch https://hackerone.com/databricks/thanks and list the top 5 hackers with rep scores
```

The filter uses `CHROMIUM_PATH` from the environment (set to `${pkgs.chromium}/bin/chromium` in `open-webui.nix`). This is activated by `nixos-rebuild switch` — the bootstrap handles this automatically. If you pull the repo after a fresh NixOS install and add it manually, run `sudo nixos-rebuild switch` once to wire it up.

---

## Pulling extra models

```bash
OLLAMA_HOST=http://127.0.0.1:11500 ollama pull <model>

# Re-create personas if needed
bash /etc/nixos/scripts/setup-models.sh
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

Edit files in this repo, then either:

```bash
# Option A — from Kali VM (serves files, prints command to run on NixOS)
bash deploy.sh

# Option B — directly on NixOS
sudo cp -r modules openwebui modelfiles scripts /etc/nixos/
sudo nixos-rebuild switch
bash /etc/nixos/scripts/setup-openwebui.sh
```

---

## File map

```
bootstrap.sh                  ← run this on fresh NixOS
deploy.sh                     ← serve config files from Kali to NixOS
modules/
  llm-lab.nix                 ← top-level import (nvidia + ollama + open-webui + playwright)
  nvidia.nix                  ← CUDA package overrides
  ollama.nix                  ← Ollama service config (port 11500, discoD storage)
  open-webui.nix              ← Open WebUI (port 8888, CHROMIUM_PATH, playwright env)
  playwright.nix              ← playwright-server sidecar (port 13000)
openwebui/
  url-fetcher-filter.py       ← Open WebUI filter: JS-rendered URL fetching via Chromium
modelfiles/
  gemma4.Modelfile            ← general assistant persona
  qwen3.Modelfile             ← qwen3-sec offsec persona
  offsec.Modelfile            ← (legacy) offsec persona
  roleplay.Modelfile          ← roleplay persona
home-manager/
  terminal.nix                ← zsh + starship + aliases
scripts/
  setup-models.sh             ← pull base models + create personas
  setup-openwebui.sh          ← deploy URL Fetcher Filter + create qwen3-sec workspace model
  install.sh                  ← used by deploy.sh (Kali → NixOS push)
  start.sh                    ← manual service start (if not using systemd)
```
