# Vendored from nixpkgs PR #375551 until upstream lands.
{ config
, lib
, modulesPath
, pkgs
, ...
}:

let
  cfg = config.hcloud;
in
{
  imports = [
    ./hcloud-config.nix
    "${modulesPath}/image/file-options.nix"
  ];

  config.system.nixos.tags = [ "hcloud" ];
  config.image.extension = "raw";
  config.system.build.image = import "${pkgs.path}/nixos/lib/make-disk-image.nix" {
    inherit lib config pkgs;
    inherit (config.image) baseName;
    partitionTableType = if cfg.efi then "efi" else "legacy";
    configFile = pkgs.writeText "configuration.nix" ''
      { modulesPath, ... }: {
        imports = [ ${./hcloud-config.nix} ];
      }
    '';
  };

  meta.maintainers = with lib.maintainers; [ stephank ];
}
