{ config, lib, pkgs, ... }:

{
  # ── FZF ──────────────────────────────────────────────────────────────────
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # ── ZSH ──────────────────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;

    sessionVariables = {
      OLLAMA_MODELS = "/mnt/discoD/ollamaModels";
      OLLAMA_HOST   = "http://127.0.0.1:11500";  # non-default port
    };

    history = {
      path      = "$HOME/.histfile";
      size      = 10000;
      save      = 10000;   # was 1000 — must be >= size or old entries are lost
      expireDuplicatesFirst = true;
      ignoreDups  = true;
      ignoreSpace = true;
      share       = false;
    };

    defaultKeymap = "emacs";

    # ── Autosuggestions ───────────────────────────────────────────────────
    autosuggestion = {
      enable    = true;
      highlight = "fg=#999999";
    };

    # ── Syntax highlighting (Kali color theme) ────────────────────────────
    syntaxHighlighting = {
      enable      = true;
      highlighters = [ "main" "brackets" "pattern" ];
      styles = {
        "default"                        = "none";
        "unknown-token"                  = "underline";
        "reserved-word"                  = "fg=cyan,bold";
        "suffix-alias"                   = "fg=green,underline";
        "global-alias"                   = "fg=green,bold";
        "precommand"                     = "fg=green,underline";
        "commandseparator"               = "fg=blue,bold";
        "autodirectory"                  = "fg=green,underline";
        "path"                           = "bold";
        "path_pathseparator"             = "";
        "path_prefix_pathseparator"      = "";
        "globbing"                       = "fg=blue,bold";
        "history-expansion"              = "fg=blue,bold";
        "command-substitution"           = "none";
        "command-substitution-delimiter" = "fg=magenta,bold";
        "process-substitution"           = "none";
        "process-substitution-delimiter" = "fg=magenta,bold";
        "single-hyphen-option"           = "fg=green";
        "double-hyphen-option"           = "fg=green";
        "back-quoted-argument"           = "none";
        "back-quoted-argument-delimiter" = "fg=blue,bold";
        "single-quoted-argument"         = "fg=yellow";
        "double-quoted-argument"         = "fg=yellow";
        "dollar-quoted-argument"         = "fg=yellow";
        "rc-quote"                       = "fg=magenta";
        "dollar-double-quoted-argument"  = "fg=magenta,bold";
        "back-double-quoted-argument"    = "fg=magenta,bold";
        "back-dollar-quoted-argument"    = "fg=magenta,bold";
        "assign"                         = "none";
        "redirection"                    = "fg=blue,bold";
        "comment"                        = "fg=black,bold";
        "named-fd"                       = "none";
        "numeric-fd"                     = "none";
        "arg0"                           = "fg=cyan";
        "bracket-error"                  = "fg=red,bold";
        "bracket-level-1"                = "fg=blue,bold";
        "bracket-level-2"                = "fg=green,bold";
        "bracket-level-3"                = "fg=magenta,bold";
        "bracket-level-4"                = "fg=yellow,bold";
        "bracket-level-5"                = "fg=cyan,bold";
        "cursor-matchingbracket"         = "standout";
      };
    };

    # ── oh-my-zsh (git plugin only; prompt handled by starship) ──────────
    oh-my-zsh = {
      enable  = true;
      plugins = [ "git" ];
    };

    # ── Aliases ───────────────────────────────────────────────────────────
    shellAliases = {
      # NixOS management
      nnixos   = "sudo nano /etc/nixos/configuration.nix";
      nswitch  = "sudo nixos-rebuild switch";
      nupgrade = "sudo nix-channel --update && nix-channel --update && sudo nixos-rebuild switch --upgrade && home-manager switch";
      nclean   = "sudo nix-collect-garbage && sudo nix-collect-garbage -d && nswitch";
      reboot   = "shutdown -r now";

      # Color output
      ls      = "ls --color=auto";
      ll      = "ls -l";
      la      = "ls -A";
      l       = "ls -CF";
      grep    = "grep --color=auto";
      fgrep   = "fgrep --color=auto";
      egrep   = "egrep --color=auto";
      diff    = "diff --color=auto";
      ip      = "ip --color=auto";
      history = "history 0";

      # LLM lab
      llm-sec      = "ollama run offsec";    # exploit code, tool writing   (qwen2.5-coder:14b)
      llm-analyst  = "ollama run analyst";   # CTF reasoning, kill chains   (phi4:14b)
      llm-rp       = "ollama run roleplay";  # character RP, narrative       (mistral-nemo:12b)
      llm-assist   = "ollama run gemma";     # general assistant             (gemma3:12b)
      llm-list     = "ollama list";
      llm-ps       = "ollama ps";
      llm-stop     = "ollama stop";
      gpu          = "nvtop";
      vram         = "nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader,nounits";
    };

    # ── Extra init (runs after oh-my-zsh and plugin sourcing) ────────────
    initExtra = ''
      # ── Shell options ───────────────────────────────────────────────────
      setopt autocd interactivecomments magicequalsubst nonomatch notify numericglobsort
      unsetopt beep

      # Don't split on / when deleting words (ctrl+w stops at path separators)
      WORDCHARS=''${WORDCHARS//\/}

      # ── Keybindings ─────────────────────────────────────────────────────
      bindkey ' '        magic-space              # history expansion on space
      bindkey '^U'       backward-kill-line       # ctrl+U  → kill to start of line
      bindkey '^[[3;5~'  kill-word               # ctrl+del → kill word forward
      bindkey '^[[3~'    delete-char             # del
      bindkey '^[[1;5C'  forward-word            # ctrl+→
      bindkey '^[[1;5D'  backward-word           # ctrl+←
      bindkey '^[[5~'    beginning-of-buffer-or-history  # page up
      bindkey '^[[6~'    end-of-buffer-or-history        # page down
      bindkey '^[[H'     beginning-of-line       # home
      bindkey '^[[F'     end-of-line             # end
      bindkey '^[[Z'     undo                    # shift+tab

      # ── Completion styles ────────────────────────────────────────────────
      zstyle ':completion:*:*:*:*:*' menu select
      zstyle ':completion:*' auto-description 'specify: %d'
      zstyle ':completion:*' completer _expand _complete
      zstyle ':completion:*' format 'Completing %d'
      zstyle ':completion:*' group-name '''
      zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
      zstyle ':completion:*' list-prompt '%SAt %p: Hit TAB for more, or the character to insert%s'
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
      zstyle ':completion:*' rehash true
      zstyle ':completion:*' select-prompt '%SScrolling active: current selection at %p%s'
      zstyle ':completion:*' use-compctl false
      zstyle ':completion:*' verbose true
      zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'
      zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'

      # ── LS and completion colors ─────────────────────────────────────────
      eval "$(dircolors -b)"
      export LS_COLORS="$LS_COLORS:ow=30;44:"   # readable colors on 777 dirs

      # ── Less colors ──────────────────────────────────────────────────────
      export LESS_TERMCAP_mb=$'\E[1;31m'   # blink  → bold red
      export LESS_TERMCAP_md=$'\E[1;36m'   # bold   → bold cyan
      export LESS_TERMCAP_me=$'\E[0m'
      export LESS_TERMCAP_so=$'\E[01;33m'  # standout (search highlight) → yellow
      export LESS_TERMCAP_se=$'\E[0m'
      export LESS_TERMCAP_us=$'\E[1;32m'   # underline → bold green
      export LESS_TERMCAP_ue=$'\E[0m'

      # ── Terminal window title ────────────────────────────────────────────
      case "$TERM" in
        xterm*|rxvt*|Eterm|aterm|kterm|gnome*|alacritty|foot|kitty*)
          autoload -Uz add-zsh-hook
          _set_title() { print -Pnr -- $'\e]0;%n@%m: %~\a' }
          add-zsh-hook precmd _set_title
          ;;
      esac
    '';
  };

  # ── Starship prompt ───────────────────────────────────────────────────────
  programs.starship.enable = true;

  # ── Packages ──────────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    mlocate
    nvtopPackages.nvidia
  ];
}
