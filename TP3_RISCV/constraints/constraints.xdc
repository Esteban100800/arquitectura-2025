## ============================================================
## Constraints para Basys3 - XC7A35T-1CPG236C
## Top module: RISCV_Debug_Top
## ============================================================

## Clock 100 MHz (el Clock Wizard define el create_clock internamente)
set_property PACKAGE_PIN W5      [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

## Reset - BTNC (botón central, activo alto)
set_property PACKAGE_PIN T18     [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

## UART - USB-UART bridge de la Basys3
set_property PACKAGE_PIN B18     [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]

set_property PACKAGE_PIN A18     [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]
