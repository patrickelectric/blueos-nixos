{ lib, pkgs, blueos, nixos-raspberrypi, ... }:
let
  frontend = pkgs.callPackage ../pkgs/blueos-frontend.nix { };

  # NixOS adds pid and user itself; the other paths exist only inside the docker image
  nginxConf =
    builtins.replaceStrings
      [
        "user www-data;\n"
        "pid /run/nginx.pid;\n"
        "/etc/nginx/mime.types"
        "include cors.conf;"
        "/home/pi/frontend"
        "/home/pi/tools/nginx/extensions"
      ]
      [
        ""
        ""
        "${pkgs.nginx}/conf/mime.types"
        "include ${blueos}/core/tools/nginx/cors.conf;"
        "${frontend}"
        "/var/lib/blueos/nginx-extensions"
      ]
      (builtins.readFile "${blueos}/core/tools/nginx/nginx.conf");

  firmware = nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system}.raspberrypifw;
in
{
  networking.hostName = "blueos";

  # cable_guy needs NetworkManager on D-Bus but configures eth0 and usb0 itself
  networking.networkmanager = {
    enable = true;
    dns = "none";
    unmanaged = [ "interface:eth0" "interface:usb0" ];
  };
  # grabs the autopilot serial ports
  networking.modemmanager.enable = false;

  services.avahi = {
    enable = true;
    publish = {
      enable = true;
      addresses = true;
    };
    extraServiceFiles.blueos = ''
      <?xml version="1.0" standalone='no'?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">%h</name>
        <service><type>_http._tcp</type><port>80</port></service>
        <service><type>_mavlink._udp</type><port>14550</port></service>
      </service-group>
    '';
  };

  services.openssh.enable = true;
  users.users.pi = {
    isNormalUser = true;
    initialPassword = "raspberry";
    extraGroups = [ "wheel" "dialout" "docker" "video" "i2c" ];
  };

  # Docker is only here for extensions, nginx proxies /docker/ to the socket
  virtualisation.docker.enable = true;
  users.users.nginx.extraGroups = [ "docker" ];
  services.nginx = {
    enable = true;
    config = nginxConf;
  };
  systemd.tmpfiles.rules = [ "d /var/lib/blueos/nginx-extensions 0755 root root -" ];

  hardware.i2c.enable = true;
  boot.kernelModules = [ "i2c-dev" "i2c-bcm2835" "bcm2835-v4l2" "dwc2" "g_ether" ];
  services.udev.extraRules =
    builtins.readFile "${blueos}/install/udev/100.autopilot.rules"
    + builtins.readFile "${blueos}/install/udev/110.usb-power.rules";

  # nixos-raspberrypi puts a console on serial0, which the Navigator uses.
  # mkForce because list options merge.
  boot.kernelParams = lib.mkForce [
    "console=tty1"
    "cgroup_enable=cpuset"
    "cgroup_memory=1"
    "cgroup_enable=memory"
  ];

  # The firmware package is the only overlay source the loaders read on every board
  boot.loader.raspberry-pi.useGenerationDeviceTree = false;
  boot.loader.raspberry-pi.firmwarePackage =
    pkgs.runCommand "raspberrypifw-navigator" { nativeBuildInputs = [ pkgs.dtc ]; } ''
      cp -r ${firmware} $out
      chmod -R u+w $out
      dtc -@ -I dts -O dtb -o $out/share/raspberrypi/boot/overlays/spi0-led.dtbo \
        ${blueos}/install/overlays/spi0-led.dts
    '';

  system.stateVersion = "25.11";
}
