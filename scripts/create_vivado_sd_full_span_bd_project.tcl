set origin_dir [file normalize [file join [file dirname [info script]] ..]]
set vivado_dir [file join $origin_dir vivado]
set proj_dir   [file join $vivado_dir sd_full_span_sr_bd]
set bd_name    sd_full_span_sr_system
set pl_freq_mhz 25
if {[info exists ::env(SD_FULL_SPAN_PL_FREQ_MHZ)]} {
  set pl_freq_mhz $::env(SD_FULL_SPAN_PL_FREQ_MHZ)
}

file mkdir $vivado_dir
file mkdir [file join $vivado_dir logs]
file delete -force $proj_dir

create_project sd_full_span_sr_bd $proj_dir -part xczu19eg-ffvc1760-2-i -force
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

set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* zynq_ultra_ps_e_0]
set_property -dict [list \
  CONFIG.PSU__FPGA_PL0_ENABLE {1} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ $pl_freq_mhz \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL {IOPLL} \
  CONFIG.PSU__USE__FABRIC__RST {1} \
  CONFIG.PSU__USE__M_AXI_GP0 {1} \
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
  CONFIG.PSU__SD1__PERIPHERAL__ENABLE {1} \
  CONFIG.PSU__SD1__PERIPHERAL__IO {MIO 46 .. 51} \
  CONFIG.PSU__SD1__DATA_TRANSFER_MODE {4Bit} \
  CONFIG.PSU__SD1__GRP_CD__ENABLE {1} \
  CONFIG.PSU__SD1__GRP_CD__IO {MIO 45} \
  CONFIG.PSU__SD1__GRP_WP__ENABLE {1} \
  CONFIG.PSU__SD1__GRP_WP__IO {MIO 44} \
  CONFIG.PSU__SD1__SLOT_TYPE {SD 2.0} \
  CONFIG.PSU__SD1__RESET__ENABLE {0} \
  CONFIG.PSU__SD1__GRP_POW__ENABLE {0} \
  CONFIG.PSU_SD1_INTERNAL_BUS_WIDTH {4} \
  CONFIG.SD1_BOARD_INTERFACE {custom} \
] $ps

set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:* axi_interconnect_0]
set_property -dict [list CONFIG.NUM_MI {1}] $axi_ic

set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst_ps_pl_100m]

set sr [create_bd_cell -type module -reference sr_sd_axi_lite_accel sr_sd_axi_lite_accel_0]
set_property -dict [list \
  CONFIG.IMG_W {64} \
  CONFIG.SCALE {2} \
  CONFIG.USE_FULL_OFFICIAL_SPAN {1} \
  CONFIG.VIDEO_GAIN_EN {0} \
] $sr

connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_pins sr_sd_axi_lite_accel_0/s_axi]

connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
  [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] \
  [get_bd_pins axi_interconnect_0/ACLK] \
  [get_bd_pins axi_interconnect_0/S00_ACLK] \
  [get_bd_pins axi_interconnect_0/M00_ACLK] \
  [get_bd_pins rst_ps_pl_100m/slowest_sync_clk] \
  [get_bd_pins sr_sd_axi_lite_accel_0/s_axi_aclk]

connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins rst_ps_pl_100m/ext_reset_in]
connect_bd_net [get_bd_pins rst_ps_pl_100m/peripheral_aresetn] \
  [get_bd_pins axi_interconnect_0/S00_ARESETN] \
  [get_bd_pins axi_interconnect_0/M00_ARESETN] \
  [get_bd_pins sr_sd_axi_lite_accel_0/s_axi_aresetn]
connect_bd_net [get_bd_pins rst_ps_pl_100m/interconnect_aresetn] [get_bd_pins axi_interconnect_0/ARESETN]

# 璇ラ樁娈典娇鐢ㄨ疆璇㈣鍙?REG_STATUS锛屼笉杩炴帴 irq锛屼究浜庢渶灏忕郴缁熷厛璺戦€氥€?
assign_bd_address
set sr_seg [get_bd_addr_segs -quiet sr_sd_axi_lite_accel_0/s_axi/*]
if {[llength $sr_seg] > 0} {
  assign_bd_address -offset 0xA0000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [lindex $sr_seg 0] -force
}

validate_bd_design
save_bd_design

make_wrapper -files [get_files [file join $proj_dir sd_full_span_sr_bd.srcs sources_1 bd $bd_name ${bd_name}.bd]] -top
add_files -norecurse [file join $proj_dir sd_full_span_sr_bd.gen sources_1 bd $bd_name hdl ${bd_name}_wrapper.v]
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "Created SD full official SPAN Block Design project:"
puts "  [file join $proj_dir sd_full_span_sr_bd.xpr]"
puts ""
puts "Block Design:"
puts "  $bd_name"
puts ""
puts "PS address for sr_sd_axi_lite_accel:"
puts "  0xA0000000"
puts ""
puts "PL0 clock frequency MHz:"
puts "  $pl_freq_mhz"
puts ""
puts "Next steps in Vivado:"
puts "  1. Open the project."
puts "  2. Review Zynq UltraScale+ PS DDR/board settings against FACE-ZUSSD reference design."
puts "  3. Generate bitstream."
puts "  4. Export hardware XSA for Vitis."
