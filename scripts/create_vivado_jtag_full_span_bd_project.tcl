set origin_dir [file normalize [file join [file dirname [info script]] ..]]
set vivado_dir [file join $origin_dir vivado]
set proj_dir   [file join $vivado_dir jfs]
set bd_name    jfs
set img_w      1
set scale      2
set pl_freq_mhz 25
if {[info exists ::env(JTAG_FULL_SPAN_IMG_W)]} {
  set img_w $::env(JTAG_FULL_SPAN_IMG_W)
}
if {[info exists ::env(JTAG_FULL_SPAN_SCALE)]} {
  set scale $::env(JTAG_FULL_SPAN_SCALE)
}
if {[info exists ::env(JTAG_FULL_SPAN_PL_FREQ_MHZ)]} {
  set pl_freq_mhz $::env(JTAG_FULL_SPAN_PL_FREQ_MHZ)
}

file mkdir $vivado_dir
file mkdir [file join $vivado_dir logs]
file delete -force $proj_dir

create_project jfs $proj_dir -part xczu19eg-ffvc1760-2-i -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_sources [concat \
    [glob -nocomplain [file join $origin_dir rtl span *.v]] \
    [glob -nocomplain [file join $origin_dir rtl pipeline *.v]] \
    [glob -nocomplain [file join $origin_dir rtl board *.v]] \
    [glob -nocomplain [file join $origin_dir rtl generated *.vh]] \
    [glob -nocomplain [file join $origin_dir rtl generated official_span_x2 weights *.mem]] \
    [glob -nocomplain [file join $origin_dir rtl generated official_span_x4 weights *.mem]] \
]
add_files -fileset sources_1 $rtl_sources
set_property include_dirs [list [file join $origin_dir rtl] [file join $origin_dir rtl generated]] [get_filesets sources_1]
update_compile_order -fileset sources_1

create_bd_design $bd_name
current_bd_design $bd_name

# PS only provides PL clock/reset; image data is transferred by JTAG-to-AXI Master.
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* ps]
set_property -dict [list \
  CONFIG.PSU__FPGA_PL0_ENABLE {1} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ $pl_freq_mhz \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL {IOPLL} \
  CONFIG.PSU__USE__FABRIC__RST {1} \
  CONFIG.PSU__USE__M_AXI_GP0 {0} \
  CONFIG.PSU__USE__M_AXI_GP1 {0} \
  CONFIG.PSU__USE__M_AXI_GP2 {0} \
  CONFIG.PSU__USE__S_AXI_GP0 {0} \
  CONFIG.PSU__USE__S_AXI_GP1 {0} \
  CONFIG.PSU__USE__S_AXI_GP2 {0} \
  CONFIG.PSU__USE__S_AXI_GP3 {0} \
  CONFIG.PSU__USE__S_AXI_GP4 {0} \
  CONFIG.PSU__USE__S_AXI_GP5 {0} \
  CONFIG.PSU__USE__S_AXI_GP6 {0} \
  CONFIG.PSU__USE__IRQ0 {0} \
] $ps

set jtag_axi [create_bd_cell -type ip -vlnv xilinx.com:ip:jtag_axi:* ja]
set axi_ic   [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:* ai]
set rst      [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst]

set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $axi_ic

set sr [create_bd_cell -type module -reference sr_jtag_rgb_transfer_endpoint sr0]
set_property -dict [list \
  CONFIG.IMG_W $img_w \
  CONFIG.SCALE $scale \
  CONFIG.USE_FULL_OFFICIAL_SPAN {1} \
  CONFIG.VIDEO_GAIN_EN {0} \
] $sr

connect_bd_intf_net [get_bd_intf_pins ja/M_AXI] [get_bd_intf_pins ai/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ai/M00_AXI] [get_bd_intf_pins sr0/s_axi]

connect_bd_net [get_bd_pins ps/pl_clk0] \
  [get_bd_pins ja/aclk] \
  [get_bd_pins ai/ACLK] \
  [get_bd_pins ai/S00_ACLK] \
  [get_bd_pins ai/M00_ACLK] \
  [get_bd_pins rst/slowest_sync_clk] \
  [get_bd_pins sr0/s_axi_aclk]

connect_bd_net [get_bd_pins ps/pl_resetn0] [get_bd_pins rst/ext_reset_in]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] \
  [get_bd_pins ja/aresetn] \
  [get_bd_pins ai/S00_ARESETN] \
  [get_bd_pins ai/M00_ARESETN] \
  [get_bd_pins sr0/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/interconnect_aresetn] [get_bd_pins ai/ARESETN]

assign_bd_address
set sr_seg [get_bd_addr_segs -quiet sr0/s_axi/*]
if {[llength $sr_seg] > 0} {
  assign_bd_address -offset 0xA0000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ja/Data] [lindex $sr_seg 0] -force
}

validate_bd_design
save_bd_design

make_wrapper -files [get_files [file join $proj_dir jfs.srcs sources_1 bd $bd_name ${bd_name}.bd]] -top
add_files -norecurse [file join $proj_dir jfs.gen sources_1 bd $bd_name hdl ${bd_name}_wrapper.v]
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "Created JTAG full official SPAN RGB transfer Block Design project:"
puts "  [file join $proj_dir jfs.xpr]"
puts ""
puts "Data path:"
puts "  USB-JTAG -> JTAG-to-AXI Master -> sr_jtag_rgb_transfer_endpoint -> SPAN pipeline"
puts ""
puts "JTAG AXI address for sr_jtag_rgb_transfer_endpoint:"
puts "  0xA0000000"
puts ""
puts "Full SPAN smoke image width:"
puts "  $img_w"
puts "Full SPAN scale:"
puts "  X$scale"
puts "PL0 clock frequency MHz:"
puts "  $pl_freq_mhz"
