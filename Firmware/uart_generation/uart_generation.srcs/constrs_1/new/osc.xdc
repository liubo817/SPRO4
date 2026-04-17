## ================================================================
## ZedBoard UART + Waveform Test (Oscilloscope)
## ================================================================

## ---------------- CLOCK ----------------
set_property PACKAGE_PIN Y9 [get_ports {clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk}]
create_clock -period 10.000 [get_ports {clk}]

## ---------------- UART (JA PMOD - Bank 13, 3.3V) ----------------
set_property PACKAGE_PIN Y11  [get_ports {i_rx}]   ;# JA1
set_property PACKAGE_PIN AA11 [get_ports {o_tx}]   ;# JA2

set_property IOSTANDARD LVCMOS33 [get_ports {i_rx}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_tx}]

## ---------------- PWM OUTPUT ----------------
set_property PACKAGE_PIN Y10 [get_ports {pwm_out}] ;# JA3
set_property IOSTANDARD LVCMOS33 [get_ports {pwm_out}]

## ---------------- SAWTOOTH OUTPUT (8-bit bus) ----------------
set_property PACKAGE_PIN AA9  [get_ports {saw_out[0]}] ;# JA4
set_property PACKAGE_PIN AB11 [get_ports {saw_out[1]}] ;# JA7
set_property PACKAGE_PIN AB10 [get_ports {saw_out[2]}] ;# JA8
set_property PACKAGE_PIN AB9  [get_ports {saw_out[3]}] ;# JA9
set_property PACKAGE_PIN AA8  [get_ports {saw_out[4]}] ;# JA10

# (only 5 pins available on JA → that's fine for testing)
set_property IOSTANDARD LVCMOS33 [get_ports {saw_out[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {saw_out[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {saw_out[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {saw_out[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {saw_out[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {saw_out[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {saw_out[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {saw_out[7]}]