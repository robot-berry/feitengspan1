set origin_dir [file normalize [file join [file dirname [info script]] ..]]
source [file join $origin_dir scripts create_vivado_project.tcl]
set_property top tb_sr_stream_top_x4 [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
run all
quit
