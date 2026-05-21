//Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
//Date        : Mon Mar  1 13:31:35 2021
//Host        : DESKTOP-7EF3K6H running 64-bit major release  (build 9200)
//Command     : generate_target zcu106_hpc0_dual_wrapper.bd
//Design      : zcu106_hpc0_dual_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module zcu106_hpc0_dual_wrapper
   (SPI_0_0_io0_io,
    SPI_0_0_io1_io,
    SPI_0_0_sck_io,
    SPI_0_0_ss_io,
    ddr4_rtl_0_act_n,
    ddr4_rtl_0_adr,
    ddr4_rtl_0_ba,
    ddr4_rtl_0_bg,
    ddr4_rtl_0_ck_c,
    ddr4_rtl_0_ck_t,
    ddr4_rtl_0_cke,
    ddr4_rtl_0_cs_n,
    ddr4_rtl_0_dm_n,
    ddr4_rtl_0_dq,
    ddr4_rtl_0_dqs_c,
    ddr4_rtl_0_dqs_t,
    ddr4_rtl_0_odt,
    ddr4_rtl_0_reset_n,
    ddr4_rtl_1_act_n,
    ddr4_rtl_1_adr,
    ddr4_rtl_1_ba,
    ddr4_rtl_1_bg,
    ddr4_rtl_1_ck_c,
    ddr4_rtl_1_ck_t,
    ddr4_rtl_1_cke,
    ddr4_rtl_1_cs_n,
    ddr4_rtl_1_dm_n,
    ddr4_rtl_1_dq,
    ddr4_rtl_1_dqs_c,
    ddr4_rtl_1_dqs_t,
    ddr4_rtl_1_odt,
    ddr4_rtl_1_reset_n,
    diff_clock_rtl_0_clk_n,
    diff_clock_rtl_0_clk_p,
    diff_clock_rtl_1_clk_n,
    diff_clock_rtl_1_clk_p,
    disable_ssd1_pwr,
    disable_ssd2_pwr,
    io_1a1,
    io_1a2,
    io_1a3,
    io_1a4,
    io_3a1,
    io_3a2,
    io_3a3,
    io_3a4,
    io_3a5,
    io_3a6,
    io_3a7,
    io_3a8,
    io_4a1,
    io_4a2,
    io_4a3,
    io_4a4,
    io_4a5,
    io_4a6,
    io_4a7,
    io_4a8,
    led_0,
    led_1,
    led_2,
    led_3,
    led_4,
    led_5,
    led_6,
    led_7,
    pci_exp_0_rxn,
    pci_exp_0_rxp,
    pci_exp_0_txn,
    pci_exp_0_txp,
    pci_exp_1_rxn,
    pci_exp_1_rxp,
    pci_exp_1_txn,
    pci_exp_1_txp,
    perst_0,
    perst_1,
    ref_clk_0_clk_n,
    ref_clk_0_clk_p,
    ref_clk_1_clk_n,
    ref_clk_1_clk_p,
    sw_0,
    sw_1,
    sw_2,
    sw_3,
    sw_4,
    sw_5,
    sw_6,
    sw_7);
  inout SPI_0_0_io0_io;
  inout SPI_0_0_io1_io;
  inout SPI_0_0_sck_io;
  inout SPI_0_0_ss_io;
  output ddr4_rtl_0_act_n;
  output [16:0]ddr4_rtl_0_adr;
  output [1:0]ddr4_rtl_0_ba;
  output [0:0]ddr4_rtl_0_bg;
  output [0:0]ddr4_rtl_0_ck_c;
  output [0:0]ddr4_rtl_0_ck_t;
  output [0:0]ddr4_rtl_0_cke;
  output [0:0]ddr4_rtl_0_cs_n;
  inout [7:0]ddr4_rtl_0_dm_n;
  inout [63:0]ddr4_rtl_0_dq;
  inout [7:0]ddr4_rtl_0_dqs_c;
  inout [7:0]ddr4_rtl_0_dqs_t;
  output [0:0]ddr4_rtl_0_odt;
  output ddr4_rtl_0_reset_n;
  output ddr4_rtl_1_act_n;
  output [16:0]ddr4_rtl_1_adr;
  output [1:0]ddr4_rtl_1_ba;
  output [0:0]ddr4_rtl_1_bg;
  output [0:0]ddr4_rtl_1_ck_c;
  output [0:0]ddr4_rtl_1_ck_t;
  output [0:0]ddr4_rtl_1_cke;
  output [0:0]ddr4_rtl_1_cs_n;
  inout [7:0]ddr4_rtl_1_dm_n;
  inout [63:0]ddr4_rtl_1_dq;
  inout [7:0]ddr4_rtl_1_dqs_c;
  inout [7:0]ddr4_rtl_1_dqs_t;
  output [0:0]ddr4_rtl_1_odt;
  output ddr4_rtl_1_reset_n;
  input diff_clock_rtl_0_clk_n;
  input diff_clock_rtl_0_clk_p;
  input diff_clock_rtl_1_clk_n;
  input diff_clock_rtl_1_clk_p;
  output [0:0]disable_ssd1_pwr;
  output [0:0]disable_ssd2_pwr;
  output [0:0]io_1a1;
  output [0:0]io_1a2;
  output [0:0]io_1a3;
  output [0:0]io_1a4;
  output [0:0]io_3a1;
  output [0:0]io_3a2;
  output [0:0]io_3a3;
  output [0:0]io_3a4;
  output [0:0]io_3a5;
  output [0:0]io_3a6;
  output [0:0]io_3a7;
  output [0:0]io_3a8;
  output [0:0]io_4a1;
  output [0:0]io_4a2;
  output [0:0]io_4a3;
  output [0:0]io_4a4;
  output [0:0]io_4a5;
  output [0:0]io_4a6;
  output [0:0]io_4a7;
  output [0:0]io_4a8;
  output [0:0]led_0;
  output [0:0]led_1;
  output [0:0]led_2;
  output [0:0]led_3;
  output [0:0]led_4;
  output [0:0]led_5;
  output [0:0]led_6;
  output [0:0]led_7;
  input [3:0]pci_exp_0_rxn;
  input [3:0]pci_exp_0_rxp;
  output [3:0]pci_exp_0_txn;
  output [3:0]pci_exp_0_txp;
  input [3:0]pci_exp_1_rxn;
  input [3:0]pci_exp_1_rxp;
  output [3:0]pci_exp_1_txn;
  output [3:0]pci_exp_1_txp;
  output [0:0]perst_0;
  output [0:0]perst_1;
  input [0:0]ref_clk_0_clk_n;
  input [0:0]ref_clk_0_clk_p;
  input [0:0]ref_clk_1_clk_n;
  input [0:0]ref_clk_1_clk_p;
  input [0:0]sw_0;
  input [0:0]sw_1;
  input [0:0]sw_2;
  input [0:0]sw_3;
  input [0:0]sw_4;
  input [0:0]sw_5;
  input [0:0]sw_6;
  input [0:0]sw_7;

  wire SPI_0_0_io0_i;
  wire SPI_0_0_io0_io;
  wire SPI_0_0_io0_o;
  wire SPI_0_0_io0_t;
  wire SPI_0_0_io1_i;
  wire SPI_0_0_io1_io;
  wire SPI_0_0_io1_o;
  wire SPI_0_0_io1_t;
  wire SPI_0_0_sck_i;
  wire SPI_0_0_sck_io;
  wire SPI_0_0_sck_o;
  wire SPI_0_0_sck_t;
  wire SPI_0_0_ss_i;
  wire SPI_0_0_ss_io;
  wire SPI_0_0_ss_o;
  wire SPI_0_0_ss_t;
  wire ddr4_rtl_0_act_n;
  wire [16:0]ddr4_rtl_0_adr;
  wire [1:0]ddr4_rtl_0_ba;
  wire [0:0]ddr4_rtl_0_bg;
  wire [0:0]ddr4_rtl_0_ck_c;
  wire [0:0]ddr4_rtl_0_ck_t;
  wire [0:0]ddr4_rtl_0_cke;
  wire [0:0]ddr4_rtl_0_cs_n;
  wire [7:0]ddr4_rtl_0_dm_n;
  wire [63:0]ddr4_rtl_0_dq;
  wire [7:0]ddr4_rtl_0_dqs_c;
  wire [7:0]ddr4_rtl_0_dqs_t;
  wire [0:0]ddr4_rtl_0_odt;
  wire ddr4_rtl_0_reset_n;
  wire ddr4_rtl_1_act_n;
  wire [16:0]ddr4_rtl_1_adr;
  wire [1:0]ddr4_rtl_1_ba;
  wire [0:0]ddr4_rtl_1_bg;
  wire [0:0]ddr4_rtl_1_ck_c;
  wire [0:0]ddr4_rtl_1_ck_t;
  wire [0:0]ddr4_rtl_1_cke;
  wire [0:0]ddr4_rtl_1_cs_n;
  wire [7:0]ddr4_rtl_1_dm_n;
  wire [63:0]ddr4_rtl_1_dq;
  wire [7:0]ddr4_rtl_1_dqs_c;
  wire [7:0]ddr4_rtl_1_dqs_t;
  wire [0:0]ddr4_rtl_1_odt;
  wire ddr4_rtl_1_reset_n;
  wire diff_clock_rtl_0_clk_n;
  wire diff_clock_rtl_0_clk_p;
  wire diff_clock_rtl_1_clk_n;
  wire diff_clock_rtl_1_clk_p;
  wire [0:0]disable_ssd1_pwr;
  wire [0:0]disable_ssd2_pwr;
  wire [0:0]io_1a1;
  wire [0:0]io_1a2;
  wire [0:0]io_1a3;
  wire [0:0]io_1a4;
  wire [0:0]io_3a1;
  wire [0:0]io_3a2;
  wire [0:0]io_3a3;
  wire [0:0]io_3a4;
  wire [0:0]io_3a5;
  wire [0:0]io_3a6;
  wire [0:0]io_3a7;
  wire [0:0]io_3a8;
  wire [0:0]io_4a1;
  wire [0:0]io_4a2;
  wire [0:0]io_4a3;
  wire [0:0]io_4a4;
  wire [0:0]io_4a5;
  wire [0:0]io_4a6;
  wire [0:0]io_4a7;
  wire [0:0]io_4a8;
  wire [0:0]led_0;
  wire [0:0]led_1;
  wire [0:0]led_2;
  wire [0:0]led_3;
  wire [0:0]led_4;
  wire [0:0]led_5;
  wire [0:0]led_6;
  wire [0:0]led_7;
  wire [3:0]pci_exp_0_rxn;
  wire [3:0]pci_exp_0_rxp;
  wire [3:0]pci_exp_0_txn;
  wire [3:0]pci_exp_0_txp;
  wire [3:0]pci_exp_1_rxn;
  wire [3:0]pci_exp_1_rxp;
  wire [3:0]pci_exp_1_txn;
  wire [3:0]pci_exp_1_txp;
  wire [0:0]perst_0;
  wire [0:0]perst_1;
  wire [0:0]ref_clk_0_clk_n;
  wire [0:0]ref_clk_0_clk_p;
  wire [0:0]ref_clk_1_clk_n;
  wire [0:0]ref_clk_1_clk_p;
  wire [0:0]sw_0;
  wire [0:0]sw_1;
  wire [0:0]sw_2;
  wire [0:0]sw_3;
  wire [0:0]sw_4;
  wire [0:0]sw_5;
  wire [0:0]sw_6;
  wire [0:0]sw_7;

  IOBUF SPI_0_0_io0_iobuf
       (.I(SPI_0_0_io0_o),
        .IO(SPI_0_0_io0_io),
        .O(SPI_0_0_io0_i),
        .T(SPI_0_0_io0_t));
  IOBUF SPI_0_0_io1_iobuf
       (.I(SPI_0_0_io1_o),
        .IO(SPI_0_0_io1_io),
        .O(SPI_0_0_io1_i),
        .T(SPI_0_0_io1_t));
  IOBUF SPI_0_0_sck_iobuf
       (.I(SPI_0_0_sck_o),
        .IO(SPI_0_0_sck_io),
        .O(SPI_0_0_sck_i),
        .T(SPI_0_0_sck_t));
  IOBUF SPI_0_0_ss_iobuf
       (.I(SPI_0_0_ss_o),
        .IO(SPI_0_0_ss_io),
        .O(SPI_0_0_ss_i),
        .T(SPI_0_0_ss_t));
  zcu106_hpc0_dual zcu106_hpc0_dual_i
       (.SPI_0_0_io0_i(SPI_0_0_io0_i),
        .SPI_0_0_io0_o(SPI_0_0_io0_o),
        .SPI_0_0_io0_t(SPI_0_0_io0_t),
        .SPI_0_0_io1_i(SPI_0_0_io1_i),
        .SPI_0_0_io1_o(SPI_0_0_io1_o),
        .SPI_0_0_io1_t(SPI_0_0_io1_t),
        .SPI_0_0_sck_i(SPI_0_0_sck_i),
        .SPI_0_0_sck_o(SPI_0_0_sck_o),
        .SPI_0_0_sck_t(SPI_0_0_sck_t),
        .SPI_0_0_ss_i(SPI_0_0_ss_i),
        .SPI_0_0_ss_o(SPI_0_0_ss_o),
        .SPI_0_0_ss_t(SPI_0_0_ss_t),
        .ddr4_rtl_0_act_n(ddr4_rtl_0_act_n),
        .ddr4_rtl_0_adr(ddr4_rtl_0_adr),
        .ddr4_rtl_0_ba(ddr4_rtl_0_ba),
        .ddr4_rtl_0_bg(ddr4_rtl_0_bg),
        .ddr4_rtl_0_ck_c(ddr4_rtl_0_ck_c),
        .ddr4_rtl_0_ck_t(ddr4_rtl_0_ck_t),
        .ddr4_rtl_0_cke(ddr4_rtl_0_cke),
        .ddr4_rtl_0_cs_n(ddr4_rtl_0_cs_n),
        .ddr4_rtl_0_dm_n(ddr4_rtl_0_dm_n),
        .ddr4_rtl_0_dq(ddr4_rtl_0_dq),
        .ddr4_rtl_0_dqs_c(ddr4_rtl_0_dqs_c),
        .ddr4_rtl_0_dqs_t(ddr4_rtl_0_dqs_t),
        .ddr4_rtl_0_odt(ddr4_rtl_0_odt),
        .ddr4_rtl_0_reset_n(ddr4_rtl_0_reset_n),
        .ddr4_rtl_1_act_n(ddr4_rtl_1_act_n),
        .ddr4_rtl_1_adr(ddr4_rtl_1_adr),
        .ddr4_rtl_1_ba(ddr4_rtl_1_ba),
        .ddr4_rtl_1_bg(ddr4_rtl_1_bg),
        .ddr4_rtl_1_ck_c(ddr4_rtl_1_ck_c),
        .ddr4_rtl_1_ck_t(ddr4_rtl_1_ck_t),
        .ddr4_rtl_1_cke(ddr4_rtl_1_cke),
        .ddr4_rtl_1_cs_n(ddr4_rtl_1_cs_n),
        .ddr4_rtl_1_dm_n(ddr4_rtl_1_dm_n),
        .ddr4_rtl_1_dq(ddr4_rtl_1_dq),
        .ddr4_rtl_1_dqs_c(ddr4_rtl_1_dqs_c),
        .ddr4_rtl_1_dqs_t(ddr4_rtl_1_dqs_t),
        .ddr4_rtl_1_odt(ddr4_rtl_1_odt),
        .ddr4_rtl_1_reset_n(ddr4_rtl_1_reset_n),
        .diff_clock_rtl_0_clk_n(diff_clock_rtl_0_clk_n),
        .diff_clock_rtl_0_clk_p(diff_clock_rtl_0_clk_p),
        .diff_clock_rtl_1_clk_n(diff_clock_rtl_1_clk_n),
        .diff_clock_rtl_1_clk_p(diff_clock_rtl_1_clk_p),
        .disable_ssd1_pwr(disable_ssd1_pwr),
        .disable_ssd2_pwr(disable_ssd2_pwr),
        .io_1a1(io_1a1),
        .io_1a2(io_1a2),
        .io_1a3(io_1a3),
        .io_1a4(io_1a4),
        .io_3a1(io_3a1),
        .io_3a2(io_3a2),
        .io_3a3(io_3a3),
        .io_3a4(io_3a4),
        .io_3a5(io_3a5),
        .io_3a6(io_3a6),
        .io_3a7(io_3a7),
        .io_3a8(io_3a8),
        .io_4a1(io_4a1),
        .io_4a2(io_4a2),
        .io_4a3(io_4a3),
        .io_4a4(io_4a4),
        .io_4a5(io_4a5),
        .io_4a6(io_4a6),
        .io_4a7(io_4a7),
        .io_4a8(io_4a8),
        .led_0(led_0),
        .led_1(led_1),
        .led_2(led_2),
        .led_3(led_3),
        .led_4(led_4),
        .led_5(led_5),
        .led_6(led_6),
        .led_7(led_7),
        .pci_exp_0_rxn(pci_exp_0_rxn),
        .pci_exp_0_rxp(pci_exp_0_rxp),
        .pci_exp_0_txn(pci_exp_0_txn),
        .pci_exp_0_txp(pci_exp_0_txp),
        .pci_exp_1_rxn(pci_exp_1_rxn),
        .pci_exp_1_rxp(pci_exp_1_rxp),
        .pci_exp_1_txn(pci_exp_1_txn),
        .pci_exp_1_txp(pci_exp_1_txp),
        .perst_0(perst_0),
        .perst_1(perst_1),
        .ref_clk_0_clk_n(ref_clk_0_clk_n),
        .ref_clk_0_clk_p(ref_clk_0_clk_p),
        .ref_clk_1_clk_n(ref_clk_1_clk_n),
        .ref_clk_1_clk_p(ref_clk_1_clk_p),
        .sw_0(sw_0),
        .sw_1(sw_1),
        .sw_2(sw_2),
        .sw_3(sw_3),
        .sw_4(sw_4),
        .sw_5(sw_5),
        .sw_6(sw_6),
        .sw_7(sw_7));
endmodule
