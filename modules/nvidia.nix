{ config, pkgs, lib, ... }:

{
  services.xserver.videoDrivers = lib.mkDefault [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable          = lib.mkDefault true;
    powerManagement.enable      = lib.mkDefault false;
    powerManagement.finegrained = lib.mkDefault false;
    open                        = lib.mkDefault false;
    nvidiaSettings              = lib.mkDefault true;
    package                     = lib.mkDefault config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.graphics = {
    enable      = lib.mkDefault true;
    enable32Bit = lib.mkDefault true;
    extraPackages = with pkgs; [
      libva-vdpau-driver   # was vaapiVdpau — renamed in nixos-25.11
      libvdpau-va-gl
    ];
  };

}
