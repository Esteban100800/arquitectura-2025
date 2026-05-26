## Clock 100 MHz
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports { i_clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { i_clk }];

## Reset (SW15)
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports { i_reset }];

## Data switches SW0-SW7
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports { i_sw[0] }];
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports { i_sw[1] }];
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports { i_sw[2] }];
set_property -dict { PACKAGE_PIN W17 IOSTANDARD LVCMOS33 } [get_ports { i_sw[3] }];
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports { i_sw[4] }];
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { i_sw[5] }];
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports { i_sw[6] }];
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports { i_sw[7] }];

## SW14: enviar resultado ALU por UART (flanco positivo)
set_property -dict { PACKAGE_PIN T1  IOSTANDARD LVCMOS33 } [get_ports { i_wr_send }];

## Buttons
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports { i_btn[0] }];
set_property -dict { PACKAGE_PIN T17 IOSTANDARD LVCMOS33 } [get_ports { i_btn[1] }];
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports { i_btn[2] }];
set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports { rd }];

## LEDs LD0-LD7: muestran el ultimo byte recibido por UART
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports { o_led[0] }];
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports { o_led[1] }];
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports { o_led[2] }];
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports { o_led[3] }];
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports { o_led[4] }];
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports { o_led[5] }];
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { o_led[6] }];
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports { o_led[7] }];

## LD8: Carry, LD9: Zero
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports { o_carry }];
set_property -dict { PACKAGE_PIN V3  IOSTANDARD LVCMOS33 } [get_ports { o_zero }];

## UART
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports { rx }];
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports { tx }];
