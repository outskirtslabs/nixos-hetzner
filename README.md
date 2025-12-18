# NixOS with Determinate Nix for Hetzner Cloud

This repo makes available NixOS Hetzner Cloud images containing [Determinate
Nix][det-nix]

This repo was inspired by [Determinate Systems][detsys]'s [repo for AWS
AMIs][nixos-amis]

Images are available for these systems:

- `x86_64-linux`
- `aarch64-linux`

On both systems, the images have these tools installed:

- [Determinate Nix][det-nix], Determinate Systems' validated and secure [Nix]
  distribution for enterprises. This includes [Determinate Nixd][dnixd], a
  utility that enables you to log in to [FlakeHub] from AWS using only this
  command (amongst other tasks):

  ```shell
  determinate-nixd login token --token-file <path to token>
  ```

  Once logged in, your VM can access [FlakeHub Cache][cache] and [private
  flakes][private-flakes] for your organization.

- [fh], the CLI for [FlakeHub]. You can use fh for things like
  [applying][fh-apply-nixos] NixOS configurations uploaded to [FlakeHub
  Cache][cache]. Here's an example:

  ```shell
  determinate-nixd login token --token-file <path to token>
  fh apply nixos "my-org/my-flake/*#nixosConfigurations.my-nixos-configuration-output"
  ```

## Example

For a detailed example of deploying NixOS systems to [HCloud] using these images, see our [nixos-hetzner-demo] repo.

## Changelog

-> [CHANGELOG.md](./CHANGELOG.md)

## Deployment

You can deploy [HCloud] instances based on the Determinate Nix images using a
variety of tools, such as [Opentofu](#opentofu).

### OpenTofu

You can use the NixOS images for [HCloud] in a [OpenTofu] configuration like
this:

```hcl
...TODO...
```

## License: Apache License 2.0

Copyright © 2025 Casey Link <casey@outskirtslabs.com>

Distributed under the [Apache-2.0](https://spdx.org/licenses/Apache-2.0.html).

[fh-apply-nixos]: https://docs.determinate.systems/flakehub/cli#apply-nixos
[cache]: https://docs.determinate.systems/flakehub/cache
[nixos-hetzner-demo]: https://github.com/outskirtslabs/nixos-hetzner-demo
[det-nix]: https://docs.determinate.systems/determinate-nix
[detsys]: https://determinate.systems
[dnixd]: https://docs.determinate.systems/determinate-nix#determinate-nixd
[ec2]: https://aws.amazon.com/ec2
[hcoud]: https://www.hetzner.com/cloud
[fh]: https://docs.determinate.systems/flakehub/cli
[fh-apply]: https://docs.determinate.systems/flakehub/cli#apply
[flakehub]: https://flakehub.com
[nix]: https://docs.determinate.systems/determinate-nix
[nixos]: https://zero-to-nix.com/concepts/nixos
[opentofu]: https://opentofu.org
[private-flakes]: https://docs.determinate.systems/flakehub/private-flakes
[opentofu]: https://opentofu.org
[nixos-amis]: https://github.com/DeterminateSystems/nixos-amis
