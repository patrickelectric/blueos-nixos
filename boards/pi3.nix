# install/boards/bcm_28xx.sh
{ ... }:
{
  hardware.raspberry-pi.config.all = {
    base-dt-params = {
      i2c_arm = { enable = true; value = "on"; };
      spi = { enable = true; value = "on"; };
    };
    dt-overlays = {
      spi1-3cs.enable = true;
      uart1.enable = true;
    };
  };
}
