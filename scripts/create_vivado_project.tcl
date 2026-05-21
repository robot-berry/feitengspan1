set origin_dir [file normalize [file join [file dirname [info script]] ..]]
set proj_dir   [file join $origin_dir build vivado_sr_accel]

file mkdir $proj_dir
create_project sr_accel $proj_dir -part xczu19eg-ffvc1760-2-i -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -fileset sources_1 [glob -nocomplain [file join $origin_dir rtl *.sv]]
add_files -fileset constrs_1 [file join $origin_dir constraints face_zussd_demo.xdc]
set_property top sr_board_demo_top [current_fileset]

add_files -fileset sim_1 [glob -nocomplain [file join $origin_dir sim *.sv]]
set_property top tb_sr_stream_top [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Created project at $proj_dir"
puts "Run simulation: launch_simulation"
puts "Run synthesis:  launch_runs synth_1 -jobs 8"
puts "Run bitstream:  launch_runs impl_1 -to_step write_bitstream -jobs 8"
