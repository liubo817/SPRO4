transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+osc  -L xil_defaultlib -L secureip -O5 xil_defaultlib.osc

do {osc.udo}

run 1000ns

endsim

quit -force
