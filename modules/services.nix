# core/start-blueos-core at BlueOS 1.4.7, one unit per service
{
  lib,
  pkgs,
  blueos,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
  ...
}:
let
  tools = pkgs.callPackage ../pkgs/blueos-tools.nix { };
  venv = pkgs.callPackage ../pkgs/blueos-core.nix {
    inherit
      blueos
      uv2nix
      pyproject-nix
      pyproject-build-systems
      ;
  };
  python = name: args: "${venv}/bin/python ${blueos}/core/services/${name}/main.py ${args}";

  mcm = pkgs.callPackage ../pkgs/mavlink-camera-manager.nix { };
  # nothing wraps a foreign binary, so it needs to be told where the plugins are
  gstPlugins = lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" (
    with pkgs.gst_all_1;
    [
      gstreamer
      gst-plugins-base
      gst-plugins-good
      gst-plugins-bad
      gst-plugins-ugly
      gst-libav
      gst-plugins-rs
      pkgs.libcamera
    ]
  );
  zenoh = pkgs.callPackage ../pkgs/zenoh.nix { };

  # core/tools/zenoh/blueos-zenoh.json5 plus where to find the rest plugin
  zenohConfig = pkgs.writeText "blueos-zenoh.json5" ''
    {
      plugins_loading: { enabled: true, search_dirs: ["${zenoh}/lib"] },
      plugins: { rest: { http_port: 7117 } }
    }
  '';

  logs = "/var/logs/blueos/services";

  service =
    name:
    {
      exec,
      memoryMax ? null,
      nice ? 0,
      user ? "root",
      path ? [ ],
      preStart ? "",
      environment ? { },
    }:
    {
      description = "BlueOS ${name}";
      wantedBy = [ "blueos.target" ];
      partOf = [ "blueos.target" ];
      after = [ "network.target" ];
      # units only get coreutils by default, the services call tools from the system profile
      path = [ "/run/current-system/sw" ] ++ path;
      environment = {
        MAV_SYSTEM_ID = "1";
        MAV_COMPONENT_ID_ONBOARD_COMPUTER4 = "194";
        RUST_BACKTRACE = "1";
      }
      // environment;
      preStart = "mkdir -p ${logs}/${name}\n" + preStart;
      serviceConfig = {
        ExecStart = exec;
        Restart = "always";
        RestartSec = 1;
        Nice = nice;
        User = user;
        WorkingDirectory = "/";
      }
      // lib.optionalAttrs (memoryMax != null) { MemoryMax = "${toString memoryMax}M"; };
    };
in
{
  # bridget and ping run unprivileged in the docker image too
  users.users.blueos = {
    isSystemUser = true;
    group = "blueos";
    extraGroups = [ "dialout" ];
  };
  users.groups.blueos = { };

  systemd.targets.blueos = {
    description = "BlueOS";
    wantedBy = [ "multi-user.target" ];
  };

  systemd.tmpfiles.rules = [
    "d ${logs} 0777 root root -"
    "d /usr/blueos/userdata/settings 0777 root root -"
    "d /etc/blueos 0755 root root -"
    "d /etc/filebrowser 0755 root root -"
    "d /shortcuts 0755 root root -"
    "L /shortcuts/system_logs - - - - ${logs}"
  ];

  systemd.services = {
    blueos-hardware-uuid = {
      wantedBy = [ "blueos.target" ];
      before = [ "blueos.target" ];
      serviceConfig.Type = "oneshot";
      script = "${tools}/bin/machineid-cli --key blueos --parts cpu-cores cpuid mac-address > /etc/blueos/hardware-uuid";
    };

    ardupilot-manager = service "autopilot" {
      nice = -19;
      exec = python "ardupilot_manager" "";
    };
    video = service "video" {
      nice = -19;
      environment.GST_PLUGIN_SYSTEM_PATH_1_0 = gstPlugins;
      exec = "${mcm}/bin/mavlink-camera-manager --default-settings BlueROVUDP --mavlink tcpout:127.0.0.1:5777 --mavlink-system-id 1 --mavlink-camera-component-id-range=100-105 --gst-feature-rank omxh264enc=0,v4l2h264enc=250,x264enc=260 --log-path ${logs}/mavlink-camera-manager --stun-server stun://stun.l.google.com:19302 --enable-realtime-threads --verbose";
    };
    cable-guy = service "cable_guy" {
      exec = python "cable_guy" "";
    };
    kraken = service "kraken" {
      nice = 19;
      exec = python "kraken" "";
    };
    wifi = service "wifi" {
      nice = 19;
      exec = python "wifi" "--socket wlan0";
    };
    beacon = service "beacon" {
      memoryMax = 250;
      exec = python "beacon" "";
    };
    bridget = service "bridget" {
      nice = 19;
      user = "blueos";
      exec = python "bridget" "";
    };
    commander = service "commander" {
      memoryMax = 250;
      exec = python "commander" "";
    };
    nmea-injector = service "nmea_injector" {
      memoryMax = 250;
      nice = 19;
      exec = python "nmea_injector" "";
    };
    helper = service "helper" {
      memoryMax = 250;
      exec = python "helper" "";
    };
    pardal = service "pardal" {
      memoryMax = 250;
      nice = 19;
      exec = python "pardal" "";
    };
    ping = service "ping" {
      nice = 19;
      user = "blueos";
      exec = python "ping" "";
    };
    log-zipper = service "log_zipper" {
      memoryMax = 250;
      nice = 19;
      exec = python "log_zipper" "'/shortcuts/system_logs/**/*.log' --max-age-minutes 60";
    };
    bag-of-holding = service "bag_of_holding" {
      memoryMax = 250;
      exec = python "bag_of_holding" "";
    };

    zenohd = service "zenohd" {
      exec = "${zenoh}/bin/zenohd -c ${zenohConfig}";
    };

    mavlink2rest = service "mavlink2rest" {
      exec = "${tools}/bin/mavlink2rest --connect=udpout:127.0.0.1:14001 --server [::]:6040 --system-id 1 --component-id 194";
    };

    linux2rest = service "linux2rest" {
      memoryMax = 250;
      exec = "${tools}/bin/linux2rest --log-path ${logs}/linux2rest --log-settings netstat=30,platform=10,serial-ports=10,system-cpu=10,system-disk=30,system-info=10,system-memory=10,system-network=10,system-process=60,system-temperature=10,system-unix-time-seconds=10";
    };

    iperf3 = service "iperf3" {
      memoryMax = 250;
      exec = "${pkgs.iperf3}/bin/iperf3 --server --port 5201";
    };

    filebrowser = service "filebrowser" {
      memoryMax = 250;
      nice = 19;
      path = [ pkgs.filebrowser ];
      # core/tools/filebrowser/bootstrap.sh
      preStart = ''
        if [ ! -f /etc/filebrowser/filebrowser.db ]; then
          filebrowser config init --address=0.0.0.0 --port=7777 --auth.method=noauth --log=stdout --root=/shortcuts --database=/etc/filebrowser/filebrowser.db
          filebrowser users add pi raspberry --database=/etc/filebrowser/filebrowser.db
        fi
      '';
      exec = "${pkgs.filebrowser}/bin/filebrowser --database /etc/filebrowser/filebrowser.db --baseurl /file-browser";
    };

    ttyd = service "ttyd" {
      memoryMax = 250;
      nice = 19;
      path = [ pkgs.tmux ];
      # -W: ttyd 1.7 is read only without it
      exec = ''${pkgs.ttyd}/bin/ttyd -W -p 8088 ${pkgs.runtimeShell} -c "tmux attach -t user_terminal || tmux new -s user_terminal"'';
    };
  };
}
