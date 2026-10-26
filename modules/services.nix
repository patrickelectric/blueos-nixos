# core/start-blueos-core at BlueOS 1.4.7, one unit per service
{ lib, pkgs, ... }:
let
  tools = pkgs.callPackage ../pkgs/blueos-tools.nix { };
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
      path ? [ ],
      preStart ? "",
    }:
    {
      description = "BlueOS ${name}";
      wantedBy = [ "blueos.target" ];
      partOf = [ "blueos.target" ];
      after = [ "network.target" ];
      inherit path;
      environment = {
        MAV_SYSTEM_ID = "1";
        MAV_COMPONENT_ID_ONBOARD_COMPUTER4 = "194";
        RUST_BACKTRACE = "1";
      };
      preStart = "mkdir -p ${logs}/${name}\n" + preStart;
      serviceConfig = {
        ExecStart = exec;
        Restart = "always";
        RestartSec = 1;
        Nice = nice;
        WorkingDirectory = "/";
      }
      // lib.optionalAttrs (memoryMax != null) { MemoryMax = "${toString memoryMax}M"; };
    };
in
{
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
