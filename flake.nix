{
  inputs = {
    # TODO: switch this back to nixos/nixpkgs once https://github.com/NixOS/nixpkgs/pull/375551 is merged
    nixpkgs.url = "git+https://github.com/ramblurr/nixpkgs?shallow=1&ref=consolidated";

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

        packages.hcloud-smoke-test = { callPackage, ... }: callPackage ./smoke_test { };

        devShell = {
          packages =
            pkgs: with pkgs; [
              hcloud
              hcloud-upload-image
              hcloud-smoke-test
            ];
        };
        nixosConfigurations = lib.genAttrs config.systems (system: {
          inherit system;
          modules = [
            inputs.determinate.nixosModules.default
            (
              { config, modulesPath, ... }:
              {
                imports = [ (modulesPath + "/virtualisation/hcloud-image.nix") ];
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
