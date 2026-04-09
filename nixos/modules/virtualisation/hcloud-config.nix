# Vendored from nixpkgs PR #375551 until upstream lands.
{ config
, lib
, modulesPath
, pkgs
, ...
}:

let
  cfg = config.hcloud;
  dynamicHostname = config.networking.hostName == "";
in
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
  ];

  options = {
    hcloud = {
      efi = lib.mkOption {
        default = pkgs.stdenv.hostPlatform.isAarch64;
        defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isAarch64";
        internal = true;
        description = ''
          Whether the server is using EFI to boot.
        '';
      };

      networkGeneratorPackage = lib.mkPackageOption pkgs "systemd-network-generator-hcloud" { };

      fetchMetadata = lib.mkOption {
        default = false;
        description = ''
          Whether to make server metadata available as
          {file}`/run/hcloud-metadata` and {file}`/run/hcloud-userdata`.
        '';
      };
    };
  };

  config = {
    boot.growPartition = true;

    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
      autoResize = true;
    };

    fileSystems."/boot" = lib.mkIf cfg.efi {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
      options = [ "umask=0077" ];
    };

    boot.loader = {
      grub.enable = !cfg.efi;
      grub.device = "/dev/sda";
      systemd-boot.enable = cfg.efi;
      efi.canTouchEfiVariables = true;
    };

    networking.hostName = lib.mkDefault "";

    services.openssh = {
      enable = true;
      settings.PermitRootLogin = "prohibit-password";
    };

    networking.timeServers = [
      "ntp1.hetzner.de"
      "ntp2.hetzner.com"
      "ntp3.hetzner.net"
    ];

    networking.useNetworkd = lib.mkDefault true;
    systemd.packages = [ cfg.networkGeneratorPackage ];
    systemd.targets.sysinit.wants = [ "systemd-network-generator-hcloud.service" ];
    systemd.services.systemd-network-generator-hcloud = {
      serviceConfig.ExecStart = [
        ""
        (
          "${cfg.networkGeneratorPackage}/bin/systemd-network-generator-hcloud"
          + lib.optionalString dynamicHostname " --write-hostname /run/hcloud-hostname"
          + " --write-public-keys /run/hcloud-public-keys"
          + lib.optionalString cfg.fetchMetadata " --write-metadata /run/hcloud-metadata --write-userdata /run/hcloud-userdata"
        )
      ];
      postStart =
        lib.optionalString dynamicHostname ''
          if [[ -s /run/hcloud-hostname ]]; then
            echo "setting hostname..."
            ${pkgs.nettools}/bin/hostname $(</run/hcloud-hostname)
            rm /run/hcloud-hostname
          fi
        ''
        + ''
          if [[ -e /run/hcloud-public-keys ]]; then
            echo "configuring root ssh authorized keys..."
            install -o root -g root -m 0700 -d /root/.ssh/
            mv /run/hcloud-public-keys /root/.ssh/authorized_keys
          fi
        '';
    };
  };

  meta.maintainers = with lib.maintainers; [ stephank ];
}
