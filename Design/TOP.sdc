
 create_clock -name clk -period 6.0 -waveform {0 3.0} [get_ports clk]
 create_clock -name clk_1 -period 18.0 -waveform {0 9.0} [get_ports clk_1]

###############################################################################
# Clock Relationships
###############################################################################

# Set clock groups as asynchronous (handled by FIFO CDC)
set_clock_groups -asynchronous \
    -group [get_clocks clk] \
    -group [get_clocks clk_1]

# Clock uncertainty (jitter + skew margin)
# Sky130 needs more margin than advanced nodes
set_clock_uncertainty 1.0 [get_clocks clk]
set_clock_uncertainty 1.5 [get_clocks clk_1]

# Clock transition (Sky130 is slower)
set_clock_transition 0.3 [get_clocks clk]
set_clock_transition 0.5 [get_clocks clk_1]

###############################################################################
# Input/Output Delays
###############################################################################

# Input delays relative to clk (primary inputs on fast clock domain)
set input_ports [all_inputs]
set input_ports [remove_from_collection $input_ports [get_ports {clk clk_1}]]

# 40% of clk period for input delay
set_input_delay -max 2.0 -clock clk $input_ports
set_input_delay -min 0.5 -clock clk $input_ports

# Output delays relative to clk_1 (outputs from CIC on slow clock domain)
# 40% of clk_1 period for output delay
set_output_delay -max 2.0 -clock clk_1 [all_outputs]
set_output_delay -min 0.5 -clock clk_1 [all_outputs]

set_false_path -from [get_clocks clk] -to [get_clocks clk_1]
set_false_path -from [get_clocks clk_1] -to [get_clocks clk]
