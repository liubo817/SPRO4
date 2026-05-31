## ================================================================
## CLOCK
## ================================================================
set_property PACKAGE_PIN Y9 [get_ports {clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk}]
create_clock -period 10.000 [get_ports {clk}]

## ================================================================
## PWM OUTPUT
## ================================================================
set_property PACKAGE_PIN F22      [get_ports {freq_sel[0]}]
set_property PACKAGE_PIN G22      [get_ports {freq_sel[1]}]
set_property PACKAGE_PIN H22      [get_ports {freq_sel[2]}]
set_property PACKAGE_PIN F21      [get_ports {freq_sel[3]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {freq_sel[*]}]

set_property PACKAGE_PIN H19      [get_ports {duty[0]}]
set_property PACKAGE_PIN H18      [get_ports {duty[1]}]
set_property PACKAGE_PIN H17      [get_ports {duty[2]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {duty[*]}]

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
## Buck PWM OUTPUT
## ================================================================
set_property PACKAGE_PIN AA9 [get_ports {buck_out}]
set_property IOSTANDARD LVCMOS33 [get_ports {buck_out}]

## ================================================================
## STATUS SIGNAL (OPTIONAL DEBUG)
## ================================================================
# Either ignore it:
# set_property DONT_TOUCH true [get_ports {o_tx_busy}]

# OR map to LED if you want:
set_property PACKAGE_PIN T22 [get_ports {o_tx_busy}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_tx_busy}]

set_property PACKAGE_PIN T21 [get_ports {led}]
set_property IOSTANDARD LVCMOS33 [get_ports {led}]

set_property PACKAGE_PIN U22 [get_ports {led2}]    
set_property IOSTANDARD LVCMOS33 [get_ports {led2}]

set_property PACKAGE_PIN U21 [get_ports {led3}]    
set_property IOSTANDARD LVCMOS33 [get_ports {led3}]

set_property PACKAGE_PIN V22 [get_ports {led4}]    
set_property IOSTANDARD LVCMOS33 [get_ports {led4}]

set_property PACKAGE_PIN W22 [get_ports {led5}]    
set_property IOSTANDARD LVCMOS33 [get_ports {led5}]

set_property PACKAGE_PIN U19 [get_ports {led6}]    
set_property IOSTANDARD LVCMOS33 [get_ports {led6}]

## ================= RESET BUTTON =================
set_property PACKAGE_PIN T18 [get_ports {reset}]
set_property IOSTANDARD LVCMOS33 [get_ports {reset}]