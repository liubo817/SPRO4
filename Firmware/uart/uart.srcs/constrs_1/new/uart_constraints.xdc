# Clock (100MHz)
create_clock -period 10.000 -name clk_internal [get_ports clock]

# reset
set_property PACKAGE_PIN V4 [get_ports user_reset]
set_property PULLDOWN TRUE [get_ports user_reset]
set_property IOSTANDARD LVCMOS33 [get_ports user_reset]

set_false_path -from [get_ports user_reset]

# UART TX (Pmod JA1 - Pin Y11)
set_property PACKAGE_PIN Y11 [get_ports tx_top]
set_property IOSTANDARD LVCMOS33 [get_ports tx_top]

# UART RX (Pmod JA2 - Pin AA11)
set_property PACKAGE_PIN AA11 [get_ports rx_top]
set_property IOSTANDARD LVCMOS33 [get_ports rx_top]
