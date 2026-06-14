{ config, pkgs, ... }:

{
  services.ollama = {
    enable  = true;
    package = pkgs.ollama-cuda;        # nixos-25.11+: replaces acceleration = "cuda"
    host    = "127.0.0.1";
    port    = 11500;
    models  = "/mnt/discoD/ollamaModels";  # explicit path; avoids the default home/models nesting

    environmentVariables = {
      OLLAMA_ORIGINS        = "http://localhost:8888,http://127.0.0.1:8888";
      OLLAMA_KEEP_ALIVE     = "300";
      OLLAMA_NUM_PARALLEL   = "1";
      OLLAMA_FLASH_ATTENTION = "1";
    };
  };

  # ollama service user needs to be in the "users" group (gid=100) so it can
  # write to /mnt/discoD, which is NTFS-mounted with gid=100 and dmask=0002
  # Run as t4x0r (uid=1000) so it can write to the NTFS mount at /mnt/discoD
  # (NTFS via ntfs-3g presents all files as owned by uid=1000; only that uid can chtimes)
  systemd.services.ollama.serviceConfig.User  = "t4x0r";
  systemd.services.ollama.serviceConfig.Group = "users";

  # Let ollama read CUDA libs from the NVIDIA driver store path
  systemd.services.ollama.environment = {
    LD_LIBRARY_PATH = "/run/opengl-driver/lib";
  };
}
