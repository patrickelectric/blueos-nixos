# install/boards/bcm_27xx.sh
{ ... }:
{
  hardware.raspberry-pi.config.pi4 = {
    base-dt-params = {
      i2c_vc = { enable = true; value = "on"; };
      i2c_arm_baudrate = { enable = true; value = 1000000; };
      spi = { enable = true; value = "on"; };
    };
    dt-overlays = {
      uart1.enable = true;
      uart3.enable = true;
      uart4.enable = true;
      uart5.enable = true;
      i2c1.enable = true;
      i2c4 = {
        enable = true;
        params = {
          pins_6_7.enable = true;
          baudrate = { enable = true; value = 1000000; };
        };
      };
      i2c6 = {
        enable = true;
        params = {
          pins_22_23.enable = true;
          baudrate = { enable = true; value = 400000; };
        };
      };
      spi0-led.enable = true;
      spi1-3cs.enable = true;
      dwc2 = {
        enable = true;
        params.dr_mode = { enable = true; value = "otg"; };
      };
    };
  };

  # gpio= repeats a key, which the attrset above cannot express
  hardware.raspberry-pi.extra-config = ''
    [pi4]
    gpio=11,24,25=op,pu,dh
    gpio=37=op,pd,dl
  '';
}
