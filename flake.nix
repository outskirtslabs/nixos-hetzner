{
  inputs = {
    nixpkgs.url = "git+https://github.com/ramblurr/nixpkgs?shallow=1&ref=consolidated";
    flakelight.url = "github:nix-community/flakelight";
    flakelight.inputs.nixpkgs.follows = "nixpkgs";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    fh.url = "https://flakehub.com/f/DeterminateSystems/fh/0.1.*";
    flake-schemas.url = "https://flakehub.com/f/DeterminateSystems/flake-schemas/0.1.5";
  };

  outputs =
    { flakelight, ... }@inputs:
    flakelight ./. (
      {
        lib,
        config,
        outputs,
        ...
      }:
      {
        inherit inputs;
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        devShell.packages =
          pkgs: with pkgs; [
            hcloud
            hcloud-upload-image
          ];
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

        outputs = {
          # Update this, and the changelog *and* usage examples in the README, for breaking changes to the AMIs
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
