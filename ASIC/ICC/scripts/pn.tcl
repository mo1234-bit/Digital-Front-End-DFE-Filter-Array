##############################################
########### SKYWATER PDK SETUP ###############
##############################################

# NOTE: Before running this script, you MUST create Milkyway library from LEF
# See the conversion script at the end of this file

##############################################
########### 1. DESIGN SETUP ##################
##############################################

set design FIR_IIR

# SkyWater PDK paths
set sky_pdk "/home/standard_cell_libraries/skywater-pdk"
set sc_dir "$sky_pdk/sky130A/libs.ref/sky130_fd_sc_hd"
set io_dir "$sky_pdk/sky130A/libs.ref/sky130_fd_io"

# Search paths
set_app_var search_path "$sc_dir/lib \
                        $io_dir/lib \
                        /home/mohamed/Desktop/johnson/rtl"

# Library setup - Using slow corner (ss = slow-slow, 100C, 1.60V)
set_app_var link_library "* sky130_fd_sc_hd__ss_100C_1v60.db \
                            sky130_fd_io__ss_100C_1v60.db"
set_app_var target_library "sky130_fd_sc_hd__ss_100C_1v60.db"

# TLU+ files for parasitic extraction (if available, otherwise skip)
# Note: SkyWater may not have pre-made TLU+ files, you might need to generate from SPEF
if {[file exists "$sc_dir/captable/sky130_fd_sc_hd__nom_max.captable"]} {
    set tlupmax "$sc_dir/captable/sky130_fd_sc_hd__nom_max.captable"
    set tlupmin "$sc_dir/captable/sky130_fd_sc_hd__nom_min.captable"
    set tech2itf "$sc_dir/captable/sky130_fd_sc_hd.itf_map"
    
    set_tlu_plus_files -max_tluplus $tlupmax \
                       -min_tluplus $tlupmin \
                       -tech2itf_map $tech2itf
}

start_gui

# Create Milkyway library (assumes you've already converted LEF to MW)
# Reference the pre-converted Milkyway library
set mw_ref_lib "$sky_pdk/sky130A/libs.ref/sky130_fd_sc_hd/milkyway/sky130_fd_sc_hd_mw"
set mw_io_lib "$sky_pdk/sky130A/libs.ref/sky130_fd_io/milkyway/sky130_fd_io_mw"

create_mw_lib ./${design} \
              -technology $mw_ref_lib/sky130_fd_sc_hd \
              -mw_reference_library "$mw_ref_lib $mw_io_lib" \
              -hier_separator {/} \
              -bus_naming_style {[%d]} \
              -open

sh rm -rf $design

import_designs ../syn/output/${design}.v \
               -format verilog \
               -top ${design} \
               -cel ${design}

source ../syn/cons/cons.tcl
set_propagated_clock [get_clocks clk]
set_propagated_clock [get_clocks clk_1]

save_mw_cel -as ${design}_1_imported

##############################################
########### 2. Floorplan #####################
##############################################

## Create Starting Floorplan
############################
# Note: SkyWater is 130nm, so dimensions will be larger than 45nm
create_floorplan -core_utilization 0.25 \
    -start_first_row -flip_first_row \
    -left_io2core 20 -bottom_io2core 20 -right_io2core 20 -top_io2core 20

## CONSTRAINTS - SkyWater has 5 metal layers (metal1-metal5)
##############
report_ignored_layers
remove_ignored_layers -all
set_ignored_layers -max_routing_layer metal5  # SkyWater: metal1-5 only!

## Initial Virtual Flat Placement
#################################
create_fp_placement -timing_driven

save_mw_cel -as ${design}_2_fp

##################################################
########### 3. POWER NETWORK #####################
##################################################

## Defining Logical POWER/GROUND Connections
## CRITICAL: SkyWater uses VPWR/VGND, not VDD/VSS!
############################################
derive_pg_connection -power_net VPWR \
                     -ground_net VGND \
                     -power_pin VPWR \
                     -ground_pin VGND

## Define Power Ring 
## SkyWater: Use metal3-5 for power (metal1-2 for signals)
####################
set_fp_rail_constraints -set_ring -nets {VPWR VGND} \
                        -horizontal_ring_layer {metal4 metal5} \
                        -vertical_ring_layer {metal5} \
                        -ring_spacing 1.0 \
                        -ring_width 3.0 \
                        -ring_offset 5.0 \
                        -extend_strap core_ring

## Define Power Mesh 
## Use metal3-5 for power distribution
####################
set_fp_rail_constraints -add_layer -layer metal5 -direction vertical   -max_strap 50 -min_strap 10 -min_width 1.6 -spacing minimum
set_fp_rail_constraints -add_layer -layer metal4 -direction horizontal -max_strap 50 -min_strap 10 -min_width 1.6 -spacing minimum
set_fp_rail_constraints -add_layer -layer metal3 -direction vertical   -max_strap 50 -min_strap 10 -min_width 0.9 -spacing minimum

set_fp_rail_constraints -set_global

## Creating virtual PG pads
## Adjust coordinates based on your floorplan size
###########################
# Create pads around perimeter - adjust X/Y based on your die size
# Example for a smaller die (adjust as needed):
set die_width 500
set die_height 500

# Top edge
for {set x 50} {$x < $die_width} {incr x 50} {
    create_fp_virtual_pad -net VGND -point [list $x $die_height]
    create_fp_virtual_pad -net VPWR -point [list [expr $x+25] $die_height]
}

# Bottom edge
for {set x 50} {$x < $die_width} {incr x 50} {
    create_fp_virtual_pad -net VGND -point [list $x 0]
    create_fp_virtual_pad -net VPWR -point [list [expr $x+25] 0]
}

# Left edge
for {set y 50} {$y < $die_height} {incr y 50} {
    create_fp_virtual_pad -net VGND -point [list 0 $y]
    create_fp_virtual_pad -net VPWR -point [list 0 [expr $y+25]]
}

# Right edge
for {set y 50} {$y < $die_height} {incr y 50} {
    create_fp_virtual_pad -net VGND -point [list $die_width $y]
    create_fp_virtual_pad -net VPWR -point [list $die_width [expr $y+25]]
}

## Synthesize power network
## SkyWater nominal voltage: 1.8V, so 2% IR drop = 36mV
synthesize_fp_rail -nets {VPWR VGND} \
                   -synthesize_power_plan \
                   -target_voltage_drop 36 \
                   -voltage_supply 1.8 \
                   -power_budget 500

commit_fp_rail

set_preroute_drc_strategy -max_layer metal5
preroute_standard_cells -fill_empty_rows -remove_floating_pieces

## Analyze IR-drop
analyze_fp_rail -nets {VPWR VGND} -power_budget 500 -voltage_supply 1.8

## Final Floorplan Assessment
create_fp_placement -incremental all

## Add Well Tie Cells (Tap cells)
## SkyWater requires tap cells every 14um (stricter than Nangate!)
#####################
add_tap_cell_array -master sky130_fd_sc_hd__tapvpwrvgnd_1 \
                   -distance 14 \
                   -pattern stagger_every_other_row

save_mw_cel -as ${design}_3_power

##############################################
########### 4. Placement #####################
##############################################
puts "start_place"

## CHECKS
#########
report_ignored_layers
check_physical_design -stage pre_place_opt
check_physical_constraints

## INITIAL PLACEMENT
####################
place_opt

## OPTIMIZATION
###############
psynopt

check_legality

# DEFINING POWER/GROUND NETS AND PINS
derive_pg_connection -power_net VPWR \
                     -ground_net VGND \
                     -power_pin VPWR \
                     -ground_pin VGND \
                     -tie

## Tie fixed values
## SkyWater tie cells: conb_1 has both HI and LO outputs
set tie_pins [get_pins -all -filter "constant_value == 0 || constant_value == 1 && name !~ V* && is_hierarchical == false"]

if {[sizeof_collection $tie_pins] > 0} {
    connect_tie_cells -objects $tie_pins \
                      -obj_type port_inst \
                      -tie_low_lib_cell */sky130_fd_sc_hd__conb_1 \
                      -tie_high_lib_cell */sky130_fd_sc_hd__conb_1
}

puts "finish_place"

save_mw_cel -as ${design}_4_placed

##############################################
########### 5. CTS       #####################
##############################################

puts "start_cts"

## CHECKS
#########
check_physical_design -stage pre_clock_opt
check_clock_tree
report_clock_tree

## CONSTRAINTS 
##############
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_16 -pin X [get_ports clk]
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_16 -pin X [get_ports clk_1]

### Set Clock Control/Targets
## SkyWater timing will be slower (130nm vs 45nm)
set_clock_tree_options -clock_trees clk \
                       -target_early_delay 0.2 \
                       -target_skew 0.5 \
                       -max_capacitance 50 \
                       -max_fanout 10 \
                       -max_transition 0.75

set_clock_tree_options -clock_trees clk \
                       -buffer_relocation true \
                       -buffer_sizing true \
                       -gate_relocation true \
                       -gate_sizing true

set_clock_tree_options -clock_trees clk_1 \
                       -target_early_delay 0.2 \
                       -target_skew 1.5 \
                       -max_capacitance 50 \
                       -max_fanout 20 \
                       -max_transition 0.75

set_clock_tree_options -clock_trees clk_1 \
                       -buffer_relocation true \
                       -buffer_sizing true \
                       -gate_relocation true \
                       -gate_sizing true

## Selection of CTS cells - SkyWater clock buffers
set_clock_tree_references -references [get_lib_cells */sky130_fd_sc_hd__clkbuf_*]

### Set Clock Physical Constraints
## Clock Non-Default Rules (NDR) - Double width/spacing
define_routing_rule sky_clock_rule \
    -widths   {metal3 0.34 metal4 0.46 metal5 3.3} \
    -spacings {metal3 0.34 metal4 0.46 metal5 3.3}

set_clock_tree_options -clock_trees clk \
                       -routing_rule sky_clock_rule \
                       -layer_list "metal3 metal4 metal5"

set_clock_tree_options -clock_trees clk_1 \
                       -routing_rule sky_clock_rule \
                       -layer_list "metal3 metal4 metal5"

## Use default routing at sinks
set_clock_tree_options -clock_trees clk   -use_default_routing_for_sinks 1
set_clock_tree_options -clock_trees clk_1 -use_default_routing_for_sinks 1

report_clock_tree -settings

## Clock Tree: Synthesis, Optimization, and Routing
####################################################

## 1- CTS
clock_opt -only_cts -no_clock_route

## Analyze
report_design_physical -utilization
report_clock_tree -summary
report_clock_tree
report_clock_timing -type summary
report_timing
report_timing -delay_type min
report_constraints -all_violators -max_delay -min_delay

## 2- CTO
clock_opt -only_psyn -no_clock_route

## 3- Clock Tree Routing
route_group -all_clock_nets

# DEFINING POWER/GROUND NETS AND PINS
derive_pg_connection -power_net VPWR \
                     -ground_net VGND \
                     -power_pin VPWR \
                     -ground_pin VGND

save_mw_cel -as ${design}_5_cts

puts "finish_cts"

##############################################
########### 6. Routing   #####################
##############################################

## Add spare cells - SkyWater cell names
insert_spare_cells -lib_cell {sky130_fd_sc_hd__nor2_4 sky130_fd_sc_hd__nand2_4} \
                   -num_instances 20 \
                   -cell_name SPARE_PREFIX_NAME \
                   -tie

set_dont_touch [all_spare_cells] true
set_attribute [all_spare_cells] is_soft_fixed true

##############################################

puts "start_route"

check_physical_design -stage pre_route_opt
all_ideal_nets
all_high_fanout -nets -threshold 100
check_routeability

set_delay_calculation_options -arnoldi_effort low

set_route_options -groute_timing_driven true \
                  -groute_incremental true \
                  -track_assign_timing_driven true \
                  -same_net_notch check_and_fix

set_si_options -route_xtalk_prevention true \
               -delta_delay true \
               -min_delta_delay true \
               -static_noise true \
               -timing_window true

## Hold fixing
set_fix_hold [all_clocks]
set_prefer -min [get_lib_cells "*/sky130_fd_sc_hd__buf_2 */sky130_fd_sc_hd__buf_1"]
set_fix_hold_options -preferred_buffer

route_opt
psynopt -only_hold_time -congestion
route_zrt_eco -open_net_driven true

verify_zrt_route
route_zrt_detail -incremental true -initial_drc_from_input true

insert_zrt_redundant_vias
verify_zrt_route
route_zrt_detail -incremental true -initial_drc_from_input true

derive_pg_connection -power_net VPWR \
                     -ground_net VGND \
                     -power_pin VPWR \
                     -ground_pin VGND

save_mw_cel -as ${design}_6_routed

puts "finish_route"

##############################################
########### 7. Finishing #####################
##############################################

## Add filler cells - SkyWater decap and fill cells
insert_stdcell_filler -cell_without_metal {sky130_fd_sc_hd__fill_8 \
                                            sky130_fd_sc_hd__fill_4 \
                                            sky130_fd_sc_hd__fill_2 \
                                            sky130_fd_sc_hd__fill_1} \
                      -connect_to_power VPWR \
                      -connect_to_ground VGND

derive_pg_connection -power_net VPWR \
                     -ground_net VGND \
                     -power_pin VPWR \
                     -ground_pin VGND

save_mw_cel -as ${design}_7_finished

save_mw_cel -as ${design}

##############################################
########### 8. Checks and Outputs ############
##############################################

verify_zrt_route
verify_lvs -ignore_floating_port -ignore_floating_net \
           -check_open_locator -check_short_locator

# GDS output - You'll need the layer map file
set gds_map "$sc_dir/gds/sky130_fd_sc_hd.layermap"
if {[file exists $gds_map]} {
    set_write_stream_options -map_layer $gds_map \
                             -output_filling fill \
                             -child_depth 20 \
                             -output_outdated_fill \
                             -output_pin {text geometry}
    
    write_stream -lib $design \
                 -format gds \
                 -cells $design \
                 ./output/${design}.gds
}

define_name_rules no_case -case_insensitive
change_names -rule no_case -hierarchy
change_names -rule verilog -hierarchy
set verilogout_no_tri true
set verilogout_equation false

write_verilog -pg -no_physical_only_cells ./output/${design}_icc.v
write_verilog -no_physical_only_cells ./output/${design}_icc_nopg.v

extract_rc
write_parasitics -output {./output/${design}.spef}

report_area > ./report/pnr_area.rpt
report_cell > ./report/pnr_cells.rpt
report_qor  > ./report/pnr_qor.rpt
report_resources > ./report/pnr_resources.rpt

close_mw_cel
close_mw_lib

exit

##############################################
######## LEF to MILKYWAY CONVERSION ##########
######## (RUN THIS FIRST, ONE TIME!) #########
##############################################

# Save this as: convert_skywater_lef_to_mw.tcl
# Run once before your main ICC flow

<<CONVERSION_SCRIPT

# Setup paths
set sky_pdk "/home/standard_cell_libraries/skywater-pdk"
set sc_dir "$sky_pdk/sky130A/libs.ref/sky130_fd_sc_hd"
set io_dir "$sky_pdk/sky130A/libs.ref/sky130_fd_io"

# Create output directory for Milkyway libraries
sh mkdir -p $sc_dir/milkyway
sh mkdir -p $io_dir/milkyway

# Convert Standard Cells
create_mw_lib -technology $sc_dir/techlef/sky130_fd_sc_hd.tlef \
              -bus_naming_style {[%d]} \
              -open \
              $sc_dir/milkyway/sky130_fd_sc_hd_mw

read_lef $sc_dir/lef/sky130_fd_sc_hd.lef
save_mw_lib
close_mw_lib

# Convert I/O cells
create_mw_lib -technology $io_dir/techlef/sky130_fd_io.tlef \
              -bus_naming_style {[%d]} \
              -open \
              $io_dir/milkyway/sky130_fd_io_mw

read_lef $io_dir/lef/sky130_fd_io.lef
save_mw_lib
close_mw_lib

puts "LEF to Milkyway conversion complete!"

CONVERSION_SCRIPT

##############################################
######## LIBERTY to DB CONVERSION ############
######## (RUN THIS FIRST, ONE TIME!) #########
##############################################

# Save this as: convert_skywater_lib_to_db.tcl
# Run with: lc_shell -f convert_skywater_lib_to_db.tcl

<<LIBERTY_CONVERSION

set sky_pdk "/home/standard_cell_libraries/skywater-pdk"
set sc_dir "$sky_pdk/sky130A/libs.ref/sky130_fd_sc_hd"
set io_dir "$sky_pdk/sky130A/libs.ref/sky130_fd_io"

# Convert standard cell libraries (all corners)
foreach lib_file [glob $sc_dir/lib/*.lib] {
    set db_file [regsub {\.lib$} $lib_file ".db"]
    read_lib $lib_file
    write_lib [get_libs] -format db -output $db_file
    remove_lib -all
    puts "Converted: $lib_file -> $db_file"
}

# Convert I/O libraries
foreach lib_file [glob $io_dir/lib/*.lib] {
    set db_file [regsub {\.lib$} $lib_file ".db"]
    read_lib $lib_file
    write_lib [get_libs] -format db -output $db_file
    remove_lib -all
    puts "Converted: $lib_file -> $db_file"
}

puts "Liberty to DB conversion complete!"
exit

LIBERTY_CONVERSION