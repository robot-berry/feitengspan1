set origin_dir [file normalize [file join [file dirname [info script]] ..]]
source [file join $origin_dir scripts create_vivado_project.tcl]
launch_simulation
run all
quit
