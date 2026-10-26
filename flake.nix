{
  description = "BlueOS on NixOS for Raspberry Pi 3, 4 and 5";

  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  inputs = {
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/28a5affc20c4a73f94af582432f4dfd179b038fe";
    blueos = {
      url = "github:bluerobotics/BlueOS/1.4.7";
      flake = false;
    };
  };

  outputs =
    { nixos-raspberrypi, ... }@inputs:
    let
      mk =
        board:
        nixos-raspberrypi.lib.nixosSystem {
          specialArgs = inputs;
          modules = [
            nixos-raspberrypi.nixosModules."raspberry-pi-${board}".base
            nixos-raspberrypi.nixosModules.sd-image
            ./boards/pi${board}.nix
            ./modules/blueos.nix
            ./modules/services.nix
          ];
        };
    in
    {
      nixosConfigurations = {
        blueos-pi3 = mk "3";
        blueos-pi4 = mk "4";
        blueos-pi5 = mk "5";
      };
    };
}
