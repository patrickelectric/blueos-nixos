{
  lib,
  pkgs,
  blueos,
  blueos-src,
  nixos-raspberrypi,
  ...
}:
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
  # Paths that only exist inside the docker image
  _module.args.blueos = pkgs.applyPatches {
    name = "blueos-src";
    src = blueos-src;
    patches = [
      ../patches/helper-nginx-paths.patch
      ../patches/cable-guy-dhcpcd.patch
    ];
  };

  networking.hostName = "blueos";

  # cable_guy needs NetworkManager on D-Bus but configures eth0 and usb0 itself
  networking.networkmanager = {
    enable = true;
    dns = "none";
    unmanaged = [ "interface:eth0" "interface:usb0" ];
  };
  # cable_guy runs its own dhcpcd on eth0, the system one would fight it
  networking.interfaces.eth0 = {
    useDHCP = false;
    ipv4.addresses = [ { address = "192.168.2.2"; prefixLength = 24; } ];
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
  # helper reads it to map ports to services
  environment.etc."blueos/nginx.conf".text = nginxConf;
  services.nginx = {
    enable = true;
    config = nginxConf;
    # gixy rejects the BlueOS config
    validateConfigFile = false;
  };
  systemd.tmpfiles.rules = [ "d /var/lib/blueos/nginx-extensions 0755 root root -" ];

  # Raspberry Pi OS ships this in its default config.txt, nixos-raspberrypi does not
  hardware.raspberry-pi.config.all.options.camera_auto_detect = {
    enable = true;
    value = true;
  };

  # What the services shell out to
  environment.systemPackages = with pkgs; [
    dhcpcd
    dnsmasq
    iw
    ifmetric
    iproute2
    util-linux
    libraspberrypi
    i2c-tools
    tmux
  ];

  hardware.i2c.enable = true;
  boot.kernelModules = [ "i2c-dev" "i2c-bcm2835" "bcm2835-v4l2" "dwc2" "g_ether" "slcan" ];
  # install/udev/110.usb-power.rules is not in the 1.4.7 tag yet
  services.udev.extraRules = builtins.readFile "${blueos}/install/udev/100.autopilot.rules" + ''
    ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"
    SUBSYSTEM=="vchiq|vcio|vc-mem", GROUP="video", MODE="0660"
  '';

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

  # core/start-blueos-core tune_performance
  boot.kernel.sysctl = {
    "net.core.wmem_max" = 16777216;
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_default" = 1048576;
    "net.core.rmem_default" = 1048576;
    "net.core.netdev_max_backlog" = 5000;
    "vm.swappiness" = 10;
  };

  # ardupilot_manager downloads glibc dynamic ArduSub binaries at runtime
  programs.nix-ld.enable = true;

  system.stateVersion = "25.11";
}
