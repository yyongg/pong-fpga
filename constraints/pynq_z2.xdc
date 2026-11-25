## PYNQ-Z2 constraints for pong_top (pins from the PYNQ-Z2 user manual)

## 125 MHz clock
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports sysclk]
create_clock -name sysclk -period 8.000 [get_ports sysclk]

## Buttons
set_property -dict { PACKAGE_PIN D19 IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN D20 IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN L20 IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property -dict { PACKAGE_PIN L19 IOSTANDARD LVCMOS33 } [get_ports {btn[3]}]
set_false_path -from [get_ports {btn[*]}]

## HDMI OUT
set_property -dict { PACKAGE_PIN L16 IOSTANDARD TMDS_33 } [get_ports hdmi_tx_clk_p]
set_property -dict { PACKAGE_PIN L17 IOSTANDARD TMDS_33 } [get_ports hdmi_tx_clk_n]
set_property -dict { PACKAGE_PIN K17 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_d_p[0]}]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_d_n[0]}]
set_property -dict { PACKAGE_PIN K19 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_d_p[1]}]
set_property -dict { PACKAGE_PIN J19 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_d_n[1]}]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_d_p[2]}]
set_property -dict { PACKAGE_PIN H18 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_d_n[2]}]
