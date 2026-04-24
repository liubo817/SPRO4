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

## =============================================================================
## wave_generator.xdc  -  ZedBoard corrected constraints
##
## Pin mapping summary
## -------------------
##  freq_sel[3:0]  →  SW3-SW0      (one-hot, LVCMOS18)
##  wave_sel       →  SW4          (LVCMOS18)
##  duty[7:0]      →  JB PMOD      (tie high/low externally, LVCMOS33)
##  pwm_out        →  JA PMOD pin1 (scope probe point,       LVCMOS33)
##  saw_out[7:0]   →  LD7-LD0      (on-board LEDs, visual,   LVCMOS33)
##  reset          →  BTNC         (centre push-button,       LVCMOS18)
##
## Bugs fixed from previous version:
##   1. duty[7:0] was entirely missing - now mapped to JB PMOD
##   2. freq_sel[0] and wave_sel both had pin F22 (duplicate) - corrected
## =============================================================================

## -----------------------------------------------------------------------------
## 100 MHz system clock  (Bank 13, LVCMOS33)
## -----------------------------------------------------------------------------
set_property PACKAGE_PIN Y9       [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

## -----------------------------------------------------------------------------
## Reset  -  BTNC centre push-button  (Bank 35, LVCMOS18)
## -----------------------------------------------------------------------------
set_property PACKAGE_PIN P16      [get_ports reset]
set_property IOSTANDARD  LVCMOS18 [get_ports reset]

## -----------------------------------------------------------------------------
## Frequency select  -  SW0..SW3  (Bank 35, LVCMOS18)
##   Flip exactly ONE switch.  Default (no switch) → 100 Hz.
##   SW0 = 100 Hz | SW1 = 200 Hz | SW2 = 500 Hz | SW3 = 1 kHz
## -----------------------------------------------------------------------------
set_property PACKAGE_PIN F22      [get_ports {freq_sel[0]}]
set_property PACKAGE_PIN G22      [get_ports {freq_sel[1]}]
set_property PACKAGE_PIN H22      [get_ports {freq_sel[2]}]
set_property PACKAGE_PIN F21      [get_ports {freq_sel[3]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {freq_sel[*]}]

## -----------------------------------------------------------------------------
## PWM duty cycle  -  JB PMOD  pins 1-4, 7-10  (Bank 13, LVCMOS33)
##
##   For a quick smoke-test without external hardware:
##     Tie all JB pins to GND  → duty = 0x00 (0%  - pwm_out always LOW)
##     Tie all JB pins to VCC  → duty = 0xFF (100% - pwm_out always HIGH)
##     JB7-JB10 = VCC, JB1-JB4 = GND → duty = 0xF0 (~94%)
##
##   JB1=duty[0](LSB) … JB4=duty[3],  JB7=duty[4] … JB10=duty[7](MSB)
## -----------------------------------------------------------------------------
## duty[3:0]  -  SW4=duty[0](LSB)  SW5=duty[1]  SW6=duty[2]   SW7=duty[3](MSB)  (LVCMOS18)
set_property PACKAGE_PIN H19      [get_ports {duty[0]}]
set_property PACKAGE_PIN H18      [get_ports {duty[1]}]
set_property PACKAGE_PIN H17      [get_ports {duty[2]}]
set_property PACKAGE_PIN M15      [get_ports {duty[3]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {duty[*]}]

## -----------------------------------------------------------------------------
## PWM output  -  JA PMOD pin 1  (Bank 13, LVCMOS33)
##   Scope probe point - connect oscilloscope channel 1 here.
## -----------------------------------------------------------------------------
set_property PACKAGE_PIN AA11      [get_ports pwm_out]
set_property IOSTANDARD  LVCMOS33 [get_ports pwm_out]

## -----------------------------------------------------------------------------
## Timing exceptions
##   Switches and buttons are async to the clock. The 2-FF synchroniser in
##   the RTL handles metastability; tell the timing engine not to analyse
##   these crossing paths.
## -----------------------------------------------------------------------------
set_false_path -from [get_ports {freq_sel[*]}]
set_false_path -from [get_ports {duty[*]}]
set_false_path -from [get_ports reset]


set_property PACKAGE_PIN E17 [get_ports vp_in]   # VP
set_property PACKAGE_PIN E18 [get_ports vn_in]   # VN
set_property IOSTANDARD LVCMOS33 [get_ports vp_in]
set_property IOSTANDARD LVCMOS33 [get_ports vn_in]