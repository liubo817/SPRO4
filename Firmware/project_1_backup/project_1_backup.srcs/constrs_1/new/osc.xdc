# ----------------------------------------------------------------------------
# Clock - Bank 13 (3.3V fixed)
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN Y9 [get_ports {clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk}]
create_clock -period 10.000 -name sys_clk [get_ports {clk}]

# ----------------------------------------------------------------------------
# UART TX - PMOD JA pin 1 - Bank 13 (3.3V fixed)
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN Y11 [get_ports {uart_txd}]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_txd}]

# ----------------------------------------------------------------------------
# Bank 13 IO standard (covers both pins above)
# ----------------------------------------------------------------------------
set_property IOSTANDARD LVCMOS33 [get_ports -of_objects [get_iobanks 13]]
```


set_property PACKAGE_PIN W11 [get_ports {pwm_out}]
set_property IOSTANDARD LVCMOS33 [get_ports {pwm_out}]

set_property PACKAGE_PIN E17 [get_ports vp_in]   # VP
set_property PACKAGE_PIN E18 [get_ports vn_in]   # VN
set_property IOSTANDARD LVCMOS33 [get_ports vp_in]
set_property IOSTANDARD LVCMOS33 [get_ports vn_in]

# LEDs LD0 to LD7
set_property PACKAGE_PIN T22 [get_ports {leds[0]}]
set_property PACKAGE_PIN T21 [get_ports {leds[1]}]
set_property PACKAGE_PIN U22 [get_ports {leds[2]}]
set_property PACKAGE_PIN U21 [get_ports {leds[3]}]
set_property PACKAGE_PIN V22 [get_ports {leds[4]}]
set_property PACKAGE_PIN W22 [get_ports {leds[5]}]
set_property PACKAGE_PIN U19 [get_ports {leds[6]}]
set_property PACKAGE_PIN U14 [get_ports {leds[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {leds[*]}]