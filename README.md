# NixOS with Determinate Nix for Hetzner Cloud

Hetzner is a price-competitive and conceptually simpler alternative to AWS and the other hyperscalers for the small orgs and teams that [I tend to work with][ol].

Using NixOS on Hetzner has traditionally been a bear, because Hetzner does not provide a NixOS image nor a straightforward way to create one.
Most folks resort to using nixos-infect, nixos-anywhere to transmogrify a debian/ubuntu instance into NixOS.

However several developments over the past year have changed the status quo:

1. [hcloud-upload-image] was released, a simple golang tool that takes a disk image as input and sideffects Hetzner Cloud in such a way that it creates a Snapshot from said image
2. [PR #375551](https://github.com/NixOS/nixpkgs/pull/375551) is making its way into nixpkgs which brings in `hcloud-upload-image` as well as the NixOS plumbing needed to produce hetzner images.
3. [FlakeHub Cache], available since late 2024, makes it *blazing* fast to copy built closures into a running system.

To be clear: I was not responsible for any of this.
I'm taking advantage of the open-source efforts of others.
This repo takes these disparate pieces and ties them together into an out-of-the-box solution for building Hetzner Cloud NixOS images.

(and yes, even this repo is a derivative as I based it on [Determinate Systems][detsys]'s [repo for AWS AMIs][nixos-amis])

---

> [!NOTE]
> This is a proof-of-concept repo maintained by me and not DetSys.
> I use something like this in prod, so what is here works, however
> don't count on me to provide the same maintenance and upkeep like DetSys does for their official AWS AMIs.

This repo makes available NixOS Hetzner Cloud images containing [Determinate Nix][det-nix]

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

For a detailed example of deploying NixOS systems to Hetzner Cloud using these
images, see our [nixos-hetzner-demo] repo.

Here's a simple way to get started:

1. [Generate a Hetzner Cloud token][new-token]
2. Build and upload:

  ```bash
  HCLOUD_TOKEN=...your hcloud token...
  ARCH=x86_64-linux
  HCLOUD_ARCH="x86"

  # or
  # ARCH=aarch64-linux
  # HCLOUD_ARCH="arm"
  nix build "github:outskirtslabs/nixos-hetzner#diskImages.$ARCH.hetzner" --print-build-logs

  # inspect the image
  ls result/*
  IMAGE_PATH=$(ls result/*.img 2>/dev/null | head -1)

  # upload to hetzner cloud
  hcloud-upload-image upload \
      --image-path="$IMAGE_PATH" \
    --architecture="$HCLOUD_ARCH" \
    --description="nixos-hetzner image"
  ```

## Changelog

-> [CHANGELOG.md](./CHANGELOG.md)


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
[flakehub cache]: https://flakehub.com/cache
[nix]: https://docs.determinate.systems/determinate-nix
[nixos]: https://zero-to-nix.com/concepts/nixos
[opentofu]: https://opentofu.org
[private-flakes]: https://docs.determinate.systems/flakehub/private-flakes
[opentofu]: https://opentofu.org
[nixos-amis]: https://github.com/DeterminateSystems/nixos-amis
[new-token]: https://docs.hetzner.com/cloud/api/getting-started/generating-api-token/
[ol]: https://outskirtslabs.com
[hcloud-upload-image]: https://github.com/apricote/hcloud-upload-image
