transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib activehdl/xil_defaultlib

vmap xil_defaultlib activehdl/xil_defaultlib

vcom -work xil_defaultlib -93  \
"../../../../project_1_backup.gen/sources_1/ip/xadc_wiz_0/xadc_wiz_0.vhd" \


