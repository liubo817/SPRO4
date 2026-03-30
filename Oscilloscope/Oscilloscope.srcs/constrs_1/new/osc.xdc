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


set_property PACKAGE_PIN Y11 [get_ports {pwm_out}]
set_property IOSTANDARD LVCMOS33 [get_ports {pwm_out}]