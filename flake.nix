{
  inputs = {
    nixpkgs.url = "git+https://github.com/ramblurr/nixpkgs?shallow=1&ref=consolidated";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    fh.url = "https://flakehub.com/f/DeterminateSystems/fh/0.1.*";
    flake-schemas.url = "https://flakehub.com/f/DeterminateSystems/flake-schemas/0.1.5";
  };

  outputs =
    { self, ... }@inputs:
    let
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      allSystems = linuxSystems;

      forSystems =
        systems: f:
        inputs.nixpkgs.lib.genAttrs systems (
          system:
          f {
            inherit system;
            pkgs = import inputs.nixpkgs {
              inherit system;
            };
            lib = inputs.nixpkgs.lib;
          }
        );

      forLinuxSystems = forSystems linuxSystems;
      forAllSystems = forSystems allSystems;
    in
    {
      # Update this, and the changelog *and* usage examples in the README, for breaking changes to the AMIs
      epoch = builtins.toString 1;

      nixosConfigurations = forLinuxSystems (
        {
          system,
          pkgs,
          lib,
          ...
        }:
        lib.nixosSystem {
          inherit system;
          modules = [
            #"${inputs.nixpkgs}/nixos/maintainers/scripts/ec2/amazon-image.nix"
            inputs.determinate.nixosModules.default
            (
              { config, modulesPath, ... }:
              {
                imports = [
                  (modulesPath + "/virtualisation/hcloud-image.nix")
                  #./nixos-modules/hetzner.nix
                ];
                system.nixos.tags = lib.mkForce [ ];

                assertions = [
                  {
                    assertion = ((builtins.match "^[0-9][0-9]\.[0-9][0-9]\..*" config.system.nixos.label) != null);
                    message = "nixos image label is incorrect";
                  }
                ];
              }
            )
          ];
        }
      );

      diskImages = forLinuxSystems (
        { system, ... }:
        {
          hetzner = self.nixosConfigurations.${system}.config.system.build.image;
        }
      );

      devShells = forAllSystems (
        {
          system,
          pkgs,
          lib,
          ...
        }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nixpkgs-fmt
              hcloud
              hcloud-upload-image
              #]
              #++ lib.optionals (builtins.elem system linuxSystems) [
              #  inputs.nixos-amis.packages.${system}.upload-ami
            ];
          };
        }
      );

      #apps = forLinuxSystems (
      #  { system, ... }:
      #  {
      #    smoke-test = inputs.nixos-amis.apps.${system}.smoke-test;
      #  }
      #);

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
