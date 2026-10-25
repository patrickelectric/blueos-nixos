# install/boards/bcm_2712.sh
{ ... }:
{
  # kernelboot keeps a single generation
  boot.loader.raspberry-pi.bootloader = "kernel";

  hardware.raspberry-pi.config.pi5 = {
    base-dt-params = {
      i2c_arm = { enable = true; value = "on"; };
      spi = { enable = true; value = "on"; };
    };
    dt-overlays = {
      uart0-pi5.enable = true;
      uart2-pi5.enable = true;
      uart3-pi5.enable = true;
      uart4-pi5.enable = true;
      i2c1.enable = true;
      i2c3-pi5 = {
        enable = true;
        params.baudrate = { enable = true; value = 400000; };
      };
      i2c-gpio = {
        enable = true;
        params = {
          i2c_gpio_sda = { enable = true; value = 22; };
          i2c_gpio_scl = { enable = true; value = 23; };
          bus = { enable = true; value = 6; };
          i2c_gpio_delay_us = { enable = true; value = 0; };
        };
      };
      spi0-led.enable = true;
      spi1-3cs.enable = true;
      dwc2 = {
        enable = true;
        params.dr_mode = { enable = true; value = "peripheral"; };
      };
    };
  };

  hardware.raspberry-pi.extra-config = ''
    [pi5]
    gpio=11,24,25=op,pu,dh
    gpio=37=op,pd,dl
  '';

  # Navigator detection probes bus 4, which is bus 3 on the Pi 5
  systemd.tmpfiles.rules = [ "L /dev/i2c-4 - - - - /dev/i2c-3" ];
}
