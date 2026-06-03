## Constraints for basys 3 FPGA

## Clock
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports { i_clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { i_clk }];

## Inputs
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports { i_reset }];

set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports { i_sw[0] }];
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports { i_sw[1] }];
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports { i_sw[2] }];
set_property -dict { PACKAGE_PIN W17 IOSTANDARD LVCMOS33 } [get_ports { i_sw[3] }];
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports { i_sw[4] }];
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { i_sw[5] }];
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports { i_sw[6] }];
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports { i_sw[7] }];

## Buttons

set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports { i_btn[0] }];
set_property -dict { PACKAGE_PIN T17 IOSTANDARD LVCMOS33 } [get_ports { i_btn[1] }];
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports { i_btn[2] }];


## Outputs
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports { o_Result[0] }];
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports { o_Result[1] }];
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports { o_Result[2] }];
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports { o_Result[3] }];
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports { o_Result[4] }];
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports { o_Result[5] }];
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { o_Result[6] }];
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports { o_Result[7] }];
set_property -dict { PACKAGE_PIN L1 IOSTANDARD LVCMOS33 } [get_ports { o_Zero }];
set_property -dict { PACKAGE_PIN P1 IOSTANDARD LVCMOS33 } [get_ports { o_Carry }];