# blueos-nixos

NixOS SD card images for Raspberry Pi 3, 4 and 5 with BlueOS running on the host. Docker is used for extensions only.

```sh
nix build --accept-flake-config .#nixosConfigurations.blueos-pi4.config.system.build.sdImage
```

Images for every tag are on the releases page.
