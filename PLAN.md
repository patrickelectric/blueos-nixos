# blueos-nixos plan

NixOS SD card images for Pi 3, Pi 4 and Pi 5 that run BlueOS core natively.
Docker stays on the image for extensions only.

## Decisions

- Base: `nvmd/nixos-raspberrypi`, pinned to a rev, not `main`. Only maintained option with vendor kernel and Pi 3/4/5, plus a binary cache. Every surveyed Pi appliance repo uses it; Thymis-io/thymis is the closest template.
- One flake, three `nixosConfigurations`: `blueos-pi3`, `blueos-pi4`, `blueos-pi5`. Same `blueos` module, different board module.
- Core services run as systemd units, not tmux. Resource limits via `MemoryMax`/`CPUQuota`. tmux stays only for ttyd's `user_terminal` session. Per-service tmux sessions become `journalctl -u`, and the web terminal is now a root shell on the real host.
- Extensions keep Docker: `virtualisation.docker.enable = true`, kraken talks to `/var/run/docker.sock` as today.
- Version chooser, bootstrap and anything else that manages the BlueOS container itself are out of scope for now. Updates are `nixos-rebuild` for developers. Docker exists on the image for one reason: extensions.
- Phase 1 reuses BlueOS release artifacts where they exist. Releases publish no frontend `dist`, only Docker image tars and full SD images, so the frontend is extracted from the arm64 `blueos-core` image tar, the way spr-networks/super takes its UI from its own image. No Pi repo uses bun2nix and its schema shifts between versions. `bun2nix` is the phase 5 experiment. Rust binaries come from each tool's own GitHub release, same URLs as `core/tools/*/bootstrap.sh`. All are musl static except linux2rest (glibc, autoPatchelf) and mavlink-camera-manager, which links GStreamer dynamically and gets its own step in phase 2. Building the rest from source is phase 5.
- CI on `ubuntu-24.04-arm`, no QEMU. Images go to GitHub releases as `.img.zst`.

## Layout

```
flake.nix               inputs: nixos-raspberrypi, uv2nix, pyproject-nix; outputs: 3 configs + packages
boards/pi3.nix          config.txt overlays and kernel modules for that board
boards/pi4.nix
boards/pi5.nix
modules/blueos.nix      users, paths, nginx, docker, networkmanager, sysctls, udev, journald
modules/services.nix    one systemd unit per BlueOS service, from a single attrset
pkgs/blueos-core.nix    uv2nix venv from core/uv.lock
pkgs/blueos-frontend.nix fetchurl of the release docker tar, extract layers, keep /home/pi/frontend
pkgs/tools.nix          fetchurl of each static binary (mavlink2rest, linux2rest, bridges, ...)
pkgs/ardupilot.nix      default ArduSub 4.5.3 firmwares from firmware.ardupilot.org, as bootstrap.sh does
.github/workflows/image.yml
```

BlueOS source is a flake input pinned to a tag, not vendored.

## Phases

### 1. Boots and serves the UI

- Flake with the three configs importing `raspberry-pi-N.base` and `sd-image`.
- Per-board `hardware.raspberry-pi.config` with the Navigator settings from `install/boards/`. nvmd renders overlays from an attrset, so order is alphabetical. Each overlay is closed with an empty `dtoverlay=` and `dtparam` lines render first, so order should not matter. If it does, paste the block from `bcm_27xx.sh` into `hardware.raspberry-pi.extra-config`.
- `boot.kernelParams = lib.mkForce [...]`. nvmd sets `console=serial0,115200n8` without `mkDefault` and list options merge, so it cannot be dropped any other way. The Navigator uses that UART. Re-add `console=tty1` and the board script's `cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory` and put `dwc2` and `g_ether` in `boot.kernelModules` instead of the cmdline `modules-load=`. `dr_mode=otg` on Pi 4 and `peripheral` on Pi 5 come from the board files. Check `/proc/cgroups` on the vendor kernel first: three surveyed hosts run dockerd on nvmd Pi 5 without those params, so they may be dead weight.
- The two `gpio=` lines on Pi 4 cannot be two keys of one attrset. They go in `hardware.raspberry-pi.extra-config`.
- `install/overlays/spi0-led.dts`: compile with `dtc` and add the `.dtbo` to the vendor `firmwarePackage`'s `overlays/` dir. Set `boot.loader.raspberry-pi.useGenerationDeviceTree = false` explicitly on all three boards so the firmware package is the single source of DTBs and overlays. nvmd defaults it to true under the `kernel` loader, so Pi 5 would otherwise copy the kernel's overlays dir and never see the dtbo. Under U-Boot, true also makes every `dtoverlay=` in `config.txt` silently ignored. nixos-uconsole's alternative is a kernel patch that adds the overlay to the kernel tree.
- Pi 5: set `boot.loader.raspberry-pi.bootloader = "kernel"`. The default `kernelboot` keeps one generation. `kernel` keeps N under `firmware/nixos/<gen>/` but has no menu: rollback is editing `os_prefix=` in `config.txt`. Pi 3 and 4 default to U-Boot, which has a generation menu.
- `hardware.i2c.enable`, `boot.kernelModules = ["i2c-dev"]` and a udev rule putting `vcio` in the `video` group, as manafishrov/firmware and aostanin/kvmd.nix do.
- `pi` user, ssh, nginx serving the prebuilt frontend. NetworkManager runs, as on Bookworm, but with `unmanaged-devices=interface:eth0;interface:usb0` and `dns=none`, which is what `blueos_startup_update` writes today. cable_guy needs NM present over D-Bus to pick its handler, but configures eth0 and usb0 itself with pyroute2 and dnsmasq. Without NM it raises `No network handler detected`; with NM managing eth0 the two fight over addresses. The wifi service's NM handler is picked the same way.
- `services.udev.extraRules` from `install/udev`: `100.autopilot.rules` gives serial adapters mode 0666 and tells ModemManager to ignore them, `110.usb-power.rules` disables USB autosuspend. NM pulls in ModemManager, so disable it outright or Pixhawk and Ping ports get grabbed.
- `networking.hostName = "blueos"` and avahi publishing `_http._tcp` on 80 and `_mavlink._udp` on 14550, as `install/network/avahi.sh` does. beacon covers `blueos.local` itself.
- Pi 5: tmpfiles symlink `/dev/i2c-4 -> /dev/i2c-3` so Navigator detection on buses 1, 4 and 6 works.
- CI builds all three images on push, uploads on tag, and pushes each `config.system.build.toplevel` to our Cachix so `nixos-rebuild` on a device never compiles.
- Stamp `/etc/blueos-version` from the git tag, as pesmarica and LNbitsBox do.
- Done when: all three boards boot, the web UI loads over ethernet.

### 2. Core services native

- uv2nix venv from `core/uv.lock`, `sourcePreference = "wheel"`, `dev` and `lint` default groups excluded. Not editable: every service has `[tool.uv] package = false`, so only commonwealth, bridges and filebrowser get installed, and uv2nix's editable overlay rejects a store-path root anyway. Units run `python services/<x>/main.py` from the BlueOS source in the store. `eclipse-zenoh` 1.9.0 ships a manylinux aarch64 wheel, so autoPatchelf should cover it along with `sdbus`, `psutil`, `pydantic-core` and `aiohttp`.
- systemd unit per service from the `start-blueos-core` list, same ports, same env.
- The other build-time downloads in `core/tools`: swagger and redoc assets into `/usr/blueos/static`, logviewer, `ardupilot_fw_uploader.py` from `ardupilot_tools/setup-python-libs.sh` (Pixhawk flashing), `scripts/` and `wifi/create_ap`. Runtime tools from the base image: `dnsmasq`, `iw`, `ifmetric`, `i2c-tools`, `iperf3`, `tmux`, `util-linux` and `iproute2` for CAN (`ldattach`, `ip link`, the `slcan` module), `libraspberrypi` for `vcgencmd` and `raspberrypi-eeprom` for `rpi-eeprom-update`, which needs `/boot/firmware` writable. Hotspot: `create_ap` needs `hostapd`, `iptables` for the captive redirect and `rfkill unblock all` at boot.
- `/var/lib/dnsmasq` tmpfiles dir for cable_guy's DHCP server leases.
- `start-blueos-core` deletes `/var/logs/blueos` when free space drops under 100 MB. Keep that as an `ExecStartPre`.
- Binaries via `fetchurl` from each tool's release. zenoh too: BlueOS runs zenohd 1.9.0 and `blueos-zenoh.json5` loads the built-in rest plugin plus `zenoh-plugin-remote-api`, a `.so` that must match zenohd's exact version. The bootstrap also fetches the webserver and filesystem-backend plugins; ship them too, they are cheap. nixpkgs has 1.10.1 with no plugins, so fetch the 1.9.0 gnu tarballs, autoPatchelf them and set `plugins_loading.search_dirs` in the config.
- mavlink-camera-manager: the release binary links `libgstreamer`, `libgstwebrtc`, `libgstrtspserver` and friends, and needs `v4l2h264enc`, `webrtcbin` and libcamera at runtime. `blueos-docker-base` builds GStreamer 1.28 and the Raspberry Pi libcamera fork from source. nixpkgs has gstreamer 1.28.7, `webrtcbin` in plugins-bad and `v4l2h264enc` in plugins-good, so autoPatchelf against `gst_all_1` and `gst-plugins-rs` should link. The unit must set `GST_PLUGIN_SYSTEM_PATH_1_0`, nothing wraps a foreign ELF. nixpkgs libcamera 0.7.2 is upstream with the rpi pipeline and `libpisp`; the base image builds the Raspberry Pi fork. Try upstream first, keep the fork as fallback. Test the Pi camera early.
- Environment and host state the start script sets up: sysctls (`net.core.wmem_max`/`rmem_max` 16 MB, `*_default` 1 MB, `netdev_max_backlog` 5000, `vm.swappiness` 10, `kernel.sched_rt_runtime_us` 950000, `net.ipv6.conf.{all,default,lo}.disable_ipv6` 1) in `boot.kernel.sysctl`; a swap file via `swapDevices` to replace `dphys-swapfile`; `MAV_SYSTEM_ID=1`, `MAV_COMPONENT_ID_ONBOARD_COMPUTER4=194` and `RUST_BACKTRACE=1` in every unit; `machineid-cli` writing `/etc/blueos/hardware-uuid` at boot; a `blueos` user in `dialout` for bridget and ping, everything else root; `Nice=-19` for autopilot and video and `LimitRTPRIO` for MCM's realtime threads; filebrowser db at `/etc/filebrowser/filebrowser.db`. Only memory limits are non-zero today (250 MB), `CPUQuota` is unused.
- nginx config: copy `core/tools/nginx/nginx.conf`, substitute `/home/pi/frontend` and `/usr/blueos` paths.
- `programs.nix-ld` so ardupilot_manager can run the downloaded `navigator64`.
- Patch BlueOS where it shells to the host:
  - `commonwealth.utils.commands`: drop ssh to localhost, run directly. Root commands are `chattr`, `tee`, `cp`, `mv`, `reboot`, `shutdown`, `timedatectl`, `date -s`, `vcgencmd`, `rpi-eeprom-update` and `raspi-config`. `raspi-config` does not exist on NixOS, so commander's legacy-camera endpoints get stubs. On NixOS `/etc/resolv.conf` is a managed symlink, so cable_guy's DNS editor needs a patch, not just a sudo rule.
  - `cable_guy/networksetup.py`: DHCP renewal shells to `dhclient`, which nixpkgs no longer has. Patch to `dhcpcd -1` or ask NM to reactivate.
  - `helper/main.py`: writes extension confs to `/home/pi/tools/nginx/extensions/` and HUPs the pid from `/var/run/nginx.pid`. NixOS nginx uses `/run/nginx/nginx.pid`. Point both at a writable dir and the right pid file.
  - Carry these as `patches/` applied to the BlueOS input until upstreamed. About six files.
  - `get_host_os()`: add NixOS.
  - `blueos_startup_update.py`, `scripts/red-pill` and `scripts/boot-probe`: drop. They patch the host from inside the container or inspect the container.
- tmpfiles rules for `/usr/blueos/{userdata,extensions,bin}`, `/etc/blueos`, `/var/logs/blueos`, `/root/.config`. BlueOS path compatibility justifies not moving to `/var/lib`. Cap journald size for SD wear.
- Budget this as the longest phase.
- Done when: vehicle connects, ArduSub flashes and runs, camera streams, wifi and ethernet config work.

### 3. Extensions

- `virtualisation.docker.enable`, pi and nginx users in `docker` group. nginx proxies `/docker/` to the socket.
- nginx `include /home/pi/tools/nginx/extensions/*.conf` kept, path adjusted.
- kraken unchanged.
- Done when: an extension installs from the store and its page opens.

### 4. Updates (out of scope for now)

- The versionchooser service does not run. The frontend calls it at startup from a few places (`App.vue`, `NewVersionNotificator`, `SelfHealthTest`, `PowerMenu`), so check those degrade to a warning rather than a broken page. If not, a stub returning the running tag is a later task.
- `nixos-rebuild switch --flake github:bluerobotics/blueos-nixos#blueos-pi4` is the update path.

### 5. Build from source (experiments)

- mavlink-server via `rustPlatform` with `SKIP_FRONTEND=1`, frontend built separately. mavlink-camera-manager the same way with `SKIP_WEB=1`, but only if the patched release binary misbehaves.
- Frontend via `bun2nix`, pinned to a commit.

## Known risks

- Pi 3: the README lists only the rpi02/4/5 installer toplevels as cached, but nvmd's Cachix push script includes `linux_rpi3`. Expect a hit. If not, one slow CI run, then our Cachix has it.
- `navigator64` is glibc dynamic. nix-ld should cover it; otherwise `autoPatchelf` in `pkgs/ardupilot.nix`.
- BlueOS patches in phase 2 should go upstream so the input stays a plain tag.
- Hardware encoders in MCM need the vendor kernel. Covered by nvmd, not by nixos-hardware.

## CI

```yaml
on:
  push:
    branches: [main]
    tags: ["v*"]
jobs:
  image:
    runs-on: ubuntu-24.04-arm
    permissions:
      contents: write
    strategy:
      matrix:
        board: [pi3, pi4, pi5]
    steps:
      - uses: actions/checkout@v7
      - uses: cachix/install-nix-action@v31
        with:
          extra_nix_config: accept-flake-config = true
      - uses: cachix/cachix-action@v17
        with:
          name: blueos
          authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}
      - run: nix build --accept-flake-config .#nixosConfigurations.blueos-${{ matrix.board }}.config.system.build.toplevel -o toplevel
      - run: nix build --accept-flake-config .#nixosConfigurations.blueos-${{ matrix.board }}.config.system.build.sdImage -o image
      - uses: softprops/action-gh-release@v3
        if: startsWith(github.ref, 'refs/tags/')
        with:
          files: image/sd-image/*.img.zst
```

cachix-action pushes the toplevel after the job, so `nixos-rebuild` on a device never compiles. Release assets are capped at 2 GiB. The compressed image should be well under that.
