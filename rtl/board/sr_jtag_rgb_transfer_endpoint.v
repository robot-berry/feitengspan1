`timescale 1ns/1ps

// USB-JTAG 图像传输验证端点。
//
// 注意：JTAG 协议本身不在普通用户 RTL 中手写实现。本模块仍然提供 AXI-Lite
// 从接口，Vivado Block Design 中的 JTAG-to-AXI Master IP 通过 USB-JTAG
// 把电脑端读写请求转换为 AXI-Lite 访问，再驱动本模块。
//
// 数据路径：
//   PC Vivado Tcl/Python
//       -> USB-JTAG
//       -> JTAG-to-AXI Master IP
//       -> 本 AXI-Lite 端点
//       -> sr_super_resolution_pipeline
//       -> 本 AXI-Lite 输出寄存器
//       -> USB-JTAG 读回 PC
//
// 寄存器协议与 sr_sd_axi_lite_accel 完全一致：
//   0x00 STATUS       bit6=input_ready, bit7=output_valid
//   0x04 INPUT_FLAGS  bit0=frame_start, bit1=line_last
//   0x08 INPUT_PIXEL  RGB888: {8'd0, R, G, B}
//   0x0c OUTPUT_PIXEL RGB888: {8'd0, R, G, B}，读取后弹出一个输出像素
//   0x14 COUNTER_IN
//   0x18 COUNTER_OUT
//   0x1c ERROR        写 bit0/bit1 清除错误标志
module sr_jtag_rgb_transfer_endpoint #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer DATA_W             = 24,
    parameter integer IMG_W              = 64,// 64x64=4096像素，12KB，完全在官方推荐的 span 内（16KB）
    //IMG_W 直接决定了每行 buffer 需要存储多少个像素特征，进而决定了 BRAM 的用量
    parameter integer SCALE              = 2,
    parameter integer USE_FULL_OFFICIAL_SPAN = 0,
    parameter integer VIDEO_GAIN_EN      = 1
) (
    input  wire                              s_axi_aclk,
    input  wire                              s_axi_aresetn,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                        s_axi_awprot,
    input  wire                              s_axi_awvalid,
    output wire                              s_axi_awready,

    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output wire                              s_axi_wready,

    output wire [1:0]                        s_axi_bresp,
    output wire                              s_axi_bvalid,
    input  wire                              s_axi_bready,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                        s_axi_arprot,
    input  wire                              s_axi_arvalid,
    output wire                              s_axi_arready,

    output wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output wire [1:0]                        s_axi_rresp,
    output wire                              s_axi_rvalid,
    input  wire                              s_axi_rready,

    output wire                              irq
);
    // 复用当前已经仿真/综合通过的 AXI-Lite 超分端点。JTAG 只是换了主机来源：
    // 原来是 PS/CPU 访问，现在是 JTAG-to-AXI Master 访问。
    sr_sd_axi_lite_accel #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .DATA_W            (DATA_W),
        .IMG_W             (IMG_W),
        .SCALE             (SCALE),
        .USE_FULL_OFFICIAL_SPAN(USE_FULL_OFFICIAL_SPAN),
        .VIDEO_GAIN_EN(VIDEO_GAIN_EN)
    ) u_axi_rgb_endpoint (
        .s_axi_aclk    (s_axi_aclk),
        .s_axi_aresetn (s_axi_aresetn),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awprot  (s_axi_awprot),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arprot  (s_axi_arprot),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .irq           (irq)
    );
endmodule
