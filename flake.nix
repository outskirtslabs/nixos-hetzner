{
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # tracks nixpkgs unstable branch

    flakelight.url = "github:nix-community/flakelight";
    flakelight.inputs.nixpkgs.follows = "nixpkgs";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    fh.url = "https://flakehub.com/f/DeterminateSystems/fh/0.1.*";
    flake-schemas.url = "https://flakehub.com/f/DeterminateSystems/flake-schemas/0.1.5";
  };

  outputs =
    { self, flakelight, ... }@inputs:
    flakelight ./. (
      { lib
      , config
      , outputs
      , ...
      }:
      {
        inherit inputs;
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];

        withOverlays = [
          self.overlays.default
        ];

        packages.hcloud-smoke-test =
          { callPackage, system, ... }:
          callPackage ./smoke_test {
            hcloud-upload-image = inputs.nixpkgs.legacyPackages.${system}.hcloud-upload-image;
          };

        devShell = {
          packages =
            pkgs: with pkgs; [
              hcloud-smoke-test
              hcloud
              hcloud-upload-image
            ];
        };
        nixosConfigurations = lib.genAttrs config.systems (system: {
          inherit system;
          modules = [
            inputs.determinate.nixosModules.default
            (
              { config, pkgs, ... }:
              {
                imports = [ ./nixos/modules/virtualisation/hcloud-image.nix ];
                environment.systemPackages = [
                  inputs.fh.packages.${system}.default
                  pkgs.git
                ];
                nixpkgs.overlays = [
                  (final: prev: {
                    systemd-network-generator-hcloud = final.callPackage ./pkgs/systemd-network-generator-hcloud/package.nix { };
                  })
                ];
                system.nixos.tags = lib.mkForce [ ];
                assertions = [
                  {
                    assertion = ((builtins.match "^[0-9][0-9]\\.[0-9][0-9]\\..*" config.system.nixos.label) != null);
                    message = "nixos image label is incorrect";
                  }
                ];
              }
            )
          ];
        });

        apps = {
          smoke-test = pkgs: {
            type = "app";
            program = "${pkgs.hcloud-smoke-test}/bin/hcloud-smoke-test";
            meta.description = "smoke test hcloud images";
          };
        };
        formatters = pkgs: {
          "*.py" = "${pkgs.python313Packages.black}/bin/black";
          "*.md" = "";
        };

        outputs = {
          # Update this, and the changelog *and* usage examples in the README, for breaking changes to the Hetzner Cloud image
          epoch = builtins.toString 1;

          diskImages = lib.genAttrs config.systems (system: {
            hetzner = outputs.nixosConfigurations.${system}.config.system.build.image;
          });

          schemas = inputs.flake-schemas.schemas // {
            diskImages = {
              version = 1;
              doc = ''
                The `diskImages` flake output contains derivations that build disk images for various execution environments.
              '';
              inventory = inputs.flake-schemas.lib.derivationsInventory "Disk image" false;
            };
          };
        };
      }
    );
}
