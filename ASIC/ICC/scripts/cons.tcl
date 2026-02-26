create_clock -name clk -period 6.0 -waveform {0 3.0} [get_ports clk]
create_clock -name clk_1 -period 18.0 -waveform {0 9.0} [get_ports clk_1]

set_clock_groups -asynchronous -group [get_clocks clk] -group [get_clocks clk_1]

set_clock_uncertainty 0.35 [get_clocks clk]
set_clock_uncertainty 0.35 [get_clocks clk_1]

set input_ports [remove_from_collection [all_inputs] [get_ports {clk clk_1}]]

set_input_delay -max 2.0 -clock [get_clocks clk] $input_ports
set_input_delay -min 0.5 -clock [get_clocks clk] $input_ports

set_output_delay -max 2.0 -clock [get_clocks clk_1] [all_outputs]
set_output_delay -min 0.5 -clock [get_clocks clk_1] [all_outputs]

set_max_transition 1.0 [current_design]
