# home-manager module — add to your home.nix imports
# Provides shell aliases and a GPU monitor for the LLM lab
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    nvtopPackages.nvidia   # GPU / VRAM usage monitor
  ];

  programs.zsh.shellAliases = {
    # Chat directly from the terminal
    llm-sec  = "ollama run offsec";
    llm-rp   = "ollama run roleplay";

    # Management
    llm-list = "ollama list";
    llm-ps   = "ollama ps";
    llm-stop = "ollama stop";

    # Quick GPU check
    gpu      = "nvtop";
    vram     = "nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader,nounits";
  };
}
