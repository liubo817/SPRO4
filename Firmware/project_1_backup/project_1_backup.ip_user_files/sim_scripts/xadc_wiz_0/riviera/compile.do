transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib riviera/xil_defaultlib

vmap xil_defaultlib riviera/xil_defaultlib

vcom -work xil_defaultlib -93  -incr \
"../../../../project_1_backup.gen/sources_1/ip/xadc_wiz_0/xadc_wiz_0.vhd" \


