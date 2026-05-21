set origin_dir [file normalize [file join [file dirname [info script]] ..]]
source [file join $origin_dir scripts create_vivado_project.tcl]
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
quit
