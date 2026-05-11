## ================================================================
## CLOCK
## ================================================================
set_property PACKAGE_PIN Y9 [get_ports {clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk}]
create_clock -period 10.000 [get_ports {clk}]

## ================================================================
## UART
## ================================================================
set_property PACKAGE_PIN Y11 [get_ports {i_rx}]
set_property PACKAGE_PIN AA11 [get_ports {o_tx}]
set_property IOSTANDARD LVCMOS33 [get_ports {i_rx}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_tx}]

## ================================================================
## PWM OUTPUT
## ================================================================
set_property PACKAGE_PIN Y10 [get_ports {pwm_out}]
set_property IOSTANDARD LVCMOS33 [get_ports {pwm_out}]

## ================================================================
## STATUS SIGNAL (OPTIONAL DEBUG)
## ================================================================
# Either ignore it:
# set_property DONT_TOUCH true [get_ports {o_tx_busy}]

# OR map to LED if you want:
set_property PACKAGE_PIN T22 [get_ports {o_tx_busy}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_tx_busy}]

## ================= RESET BUTTON =================
set_property PACKAGE_PIN T18 [get_ports {reset}]
set_property IOSTANDARD LVCMOS33 [get_ports {reset}]