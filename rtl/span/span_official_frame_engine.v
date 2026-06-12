`timescale 1ns/1ps
`include "../generated/official_span_model_config.vh"

// 官方 SPAN 帧级顺序计算引擎。
// 当前版本用于完整计算链路验证：
//   conv_1 -> 6 个 SPAB -> conv_2 -> conv_cat -> upsampler -> PixelShuffle。
// 说明：该版本采用整帧缓存和单 MAC 顺序调度，优先保证官方 44 个张量和
// Python 定点参考逐层对齐；后续再替换为多 MAC 并行阵列和行缓存流水结构。
module span_official_frame_engine #(
    parameter integer DATA_W = 24,
    parameter integer IMG_W  = 64,
    parameter integer IMG_H  = 64,
    parameter integer CH     = `OFFICIAL_SPAN_FEATURE_CHANNELS,
    parameter integer SCALE  = `OFFICIAL_SPAN_MODEL_SCALE,
    parameter integer ACC_W  = 32,
    parameter integer SCALE_SHIFT = 8
) (
    input  wire              clk,
    input  wire              rst,

    input  wire              s_valid,
    output wire              s_ready,
    input  wire [DATA_W-1:0] s_data,
    input  wire              s_user,
    input  wire              s_last,

    output reg               m_valid,
    input  wire              m_ready,
    output reg  [DATA_W-1:0] m_data,
    output wire              m_user,
    output wire              m_last,
    output reg               busy,
    output reg               done
);
    localparam integer FRAME_PIXELS = IMG_W * IMG_H;
    localparam integer HR_W = IMG_W * SCALE;
    localparam integer HR_H = IMG_H * SCALE;
    localparam integer HR_PIXELS = HR_W * HR_H;
    localparam integer UP_SUBPIXELS = SCALE * SCALE;
    localparam integer UP_CH = 3 * UP_SUBPIXELS;

    localparam integer FRAME_W = (FRAME_PIXELS <= 2) ? 1 : $clog2(FRAME_PIXELS);
    localparam integer HR_FRAME_W = (HR_PIXELS <= 2) ? 1 : $clog2(HR_PIXELS);
    localparam integer CH_W = (CH <= 2) ? 1 : $clog2(CH);
    localparam integer UP_CH_W = (UP_CH <= 2) ? 1 : $clog2(UP_CH);
    localparam integer MAX_TAPS = CH * 9;
    localparam integer TAP_W = (MAX_TAPS <= 2) ? 1 : $clog2(MAX_TAPS);
    localparam integer FEATURE_BANKS = 4;
    localparam integer FEATURE_BANK_CH = (CH + FEATURE_BANKS - 1) / FEATURE_BANKS;
    localparam integer FEATURE_BANK_SIZE = FRAME_PIXELS * FEATURE_BANK_CH;
    localparam integer FEATURE_BANK_ADDR_W = (FEATURE_BANK_SIZE <= 2) ? 1 : $clog2(FEATURE_BANK_SIZE);
    localparam integer FEATURE_BANK_RAM_DEPTH = 1 << FEATURE_BANK_ADDR_W;
    localparam integer UP_PIXEL_COUNT = FRAME_PIXELS * UP_SUBPIXELS;
    localparam integer UP_PIXEL_ADDR_W = (UP_PIXEL_COUNT <= 2) ? 1 : $clog2(UP_PIXEL_COUNT);
    localparam integer UP_PIXEL_RAM_DEPTH = 1 << UP_PIXEL_ADDR_W;

    localparam [3:0] ST_CAPTURE = 4'd0;
    localparam [3:0] ST_PREP    = 4'd1;
    localparam [3:0] ST_WEIGHT_WAIT = 4'd2;
    localparam [3:0] ST_MAC     = 4'd3;
    localparam [3:0] ST_OUTPUT  = 4'd4;
    localparam [3:0] ST_DATA_WAIT = 4'd5;
    localparam [3:0] ST_OUTPUT_WAIT = 4'd6;
    localparam [3:0] ST_OUTPUT_DATA = 4'd7;

    localparam [5:0] SRC_ZERO   = 6'd0;
    localparam [5:0] SRC_RGB_R  = 6'd1;
    localparam [5:0] SRC_RGB_G  = 6'd2;
    localparam [5:0] SRC_RGB_B  = 6'd3;
    localparam [5:0] SRC_BUF_A0 = 6'd4;
    localparam [5:0] SRC_BUF_A1 = 6'd5;
    localparam [5:0] SRC_BUF_A2 = 6'd6;
    localparam [5:0] SRC_BUF_A3 = 6'd7;
    localparam [5:0] SRC_BUF_B0 = 6'd8;
    localparam [5:0] SRC_BUF_B1 = 6'd9;
    localparam [5:0] SRC_BUF_B2 = 6'd10;
    localparam [5:0] SRC_BUF_B3 = 6'd11;
    localparam [5:0] SRC_BUF_C0 = 6'd12;
    localparam [5:0] SRC_BUF_C1 = 6'd13;
    localparam [5:0] SRC_BUF_C2 = 6'd14;
    localparam [5:0] SRC_BUF_C3 = 6'd15;
    localparam [5:0] SRC_BUF_D0 = 6'd16;
    localparam [5:0] SRC_BUF_D1 = 6'd17;
    localparam [5:0] SRC_BUF_D2 = 6'd18;
    localparam [5:0] SRC_BUF_D3 = 6'd19;
    localparam [5:0] SRC_FEAT00 = 6'd20;
    localparam [5:0] SRC_FEAT01 = 6'd21;
    localparam [5:0] SRC_FEAT02 = 6'd22;
    localparam [5:0] SRC_FEAT03 = 6'd23;
    localparam [5:0] SRC_B1_0   = 6'd24;
    localparam [5:0] SRC_B1_1   = 6'd25;
    localparam [5:0] SRC_B1_2   = 6'd26;
    localparam [5:0] SRC_B1_3   = 6'd27;
    localparam [5:0] SRC_B5_20  = 6'd28;
    localparam [5:0] SRC_B5_21  = 6'd29;
    localparam [5:0] SRC_B5_22  = 6'd30;
    localparam [5:0] SRC_B5_23  = 6'd31;
    localparam [5:0] SRC_B6_0   = 6'd32;
    localparam [5:0] SRC_B6_1   = 6'd33;
    localparam [5:0] SRC_B6_2   = 6'd34;
    localparam [5:0] SRC_B6_3   = 6'd35;

    localparam [3:0] GROUP_BUF_A = 4'd0;
    localparam [3:0] GROUP_BUF_B = 4'd1;
    localparam [3:0] GROUP_BUF_C = 4'd2;
    localparam [3:0] GROUP_BUF_D = 4'd3;
    localparam [3:0] GROUP_FEAT0 = 4'd4;
    localparam [3:0] GROUP_B1    = 4'd5;
    localparam [3:0] GROUP_B5_2  = 4'd6;
    localparam [3:0] GROUP_B6    = 4'd7;

    reg [3:0] state;
    (* ram_style = "block" *) reg [DATA_W-1:0] rgb_mem [0:FRAME_PIXELS-1];

    reg [5:0] act_rd_src;
    reg [31:0] act_rd_addr;
    reg [5:0] residual_rd_src;
    reg [31:0] residual_rd_addr;

    reg up_r_we;
    reg up_g_we;
    reg up_b_we;
    reg [UP_PIXEL_ADDR_W-1:0] up_r_waddr;
    reg [UP_PIXEL_ADDR_W-1:0] up_g_waddr;
    reg [UP_PIXEL_ADDR_W-1:0] up_b_waddr;
    reg [UP_PIXEL_ADDR_W-1:0] up_r_raddr;
    reg [UP_PIXEL_ADDR_W-1:0] up_g_raddr;
    reg [UP_PIXEL_ADDR_W-1:0] up_b_raddr;
    reg signed [7:0] up_r_wdata;
    reg signed [7:0] up_g_wdata;
    reg signed [7:0] up_b_wdata;
    wire signed [7:0] up_r_rdata;
    wire signed [7:0] up_g_rdata;
    wire signed [7:0] up_b_rdata;

`define SPAN_DECL_FEATURE_RAM(NAME) \
    reg NAME``_we; \
    reg [FEATURE_BANK_ADDR_W-1:0] NAME``_waddr; \
    reg signed [7:0] NAME``_wdata; \
    wire [FEATURE_BANK_ADDR_W-1:0] NAME``_raddr; \
    wire signed [7:0] NAME``_rdata

    `SPAN_DECL_FEATURE_RAM(buf_a0);
    `SPAN_DECL_FEATURE_RAM(buf_a1);
    `SPAN_DECL_FEATURE_RAM(buf_a2);
    `SPAN_DECL_FEATURE_RAM(buf_a3);
    `SPAN_DECL_FEATURE_RAM(buf_b0);
    `SPAN_DECL_FEATURE_RAM(buf_b1);
    `SPAN_DECL_FEATURE_RAM(buf_b2);
    `SPAN_DECL_FEATURE_RAM(buf_b3);
    `SPAN_DECL_FEATURE_RAM(buf_c0);
    `SPAN_DECL_FEATURE_RAM(buf_c1);
    `SPAN_DECL_FEATURE_RAM(buf_c2);
    `SPAN_DECL_FEATURE_RAM(buf_c3);
    `SPAN_DECL_FEATURE_RAM(buf_d0);
    `SPAN_DECL_FEATURE_RAM(buf_d1);
    `SPAN_DECL_FEATURE_RAM(buf_d2);
    `SPAN_DECL_FEATURE_RAM(buf_d3);
    `SPAN_DECL_FEATURE_RAM(feat0_mem0);
    `SPAN_DECL_FEATURE_RAM(feat0_mem1);
    `SPAN_DECL_FEATURE_RAM(feat0_mem2);
    `SPAN_DECL_FEATURE_RAM(feat0_mem3);
    `SPAN_DECL_FEATURE_RAM(b1_mem0);
    `SPAN_DECL_FEATURE_RAM(b1_mem1);
    `SPAN_DECL_FEATURE_RAM(b1_mem2);
    `SPAN_DECL_FEATURE_RAM(b1_mem3);
    `SPAN_DECL_FEATURE_RAM(b5_2_mem0);
    `SPAN_DECL_FEATURE_RAM(b5_2_mem1);
    `SPAN_DECL_FEATURE_RAM(b5_2_mem2);
    `SPAN_DECL_FEATURE_RAM(b5_2_mem3);
    `SPAN_DECL_FEATURE_RAM(b6conv_mem0);
    `SPAN_DECL_FEATURE_RAM(b6conv_mem1);
    `SPAN_DECL_FEATURE_RAM(b6conv_mem2);
    `SPAN_DECL_FEATURE_RAM(b6conv_mem3);

`define SPAN_FEATURE_RADDR(NAME, SRC_ID) \
    assign NAME``_raddr = (act_rd_src == SRC_ID) ? act_rd_addr[FEATURE_BANK_ADDR_W-1:0] : \
                          (residual_rd_src == SRC_ID) ? residual_rd_addr[FEATURE_BANK_ADDR_W-1:0] : \
                          {FEATURE_BANK_ADDR_W{1'b0}}

`define SPAN_INST_FEATURE_RAM(NAME) \
    span_sync_ram_1r1w #( \
        .DATA_W(8), \
        .DEPTH(FEATURE_BANK_RAM_DEPTH), \
        .ADDR_W(FEATURE_BANK_ADDR_W) \
    ) u_``NAME``_ram ( \
        .clk(clk), \
        .we(NAME``_we), \
        .waddr(NAME``_waddr), \
        .wdata(NAME``_wdata), \
        .raddr(NAME``_raddr), \
        .rdata(NAME``_rdata) \
    )

    `SPAN_FEATURE_RADDR(buf_a0, SRC_BUF_A0);
    `SPAN_FEATURE_RADDR(buf_a1, SRC_BUF_A1);
    `SPAN_FEATURE_RADDR(buf_a2, SRC_BUF_A2);
    `SPAN_FEATURE_RADDR(buf_a3, SRC_BUF_A3);
    `SPAN_FEATURE_RADDR(buf_b0, SRC_BUF_B0);
    `SPAN_FEATURE_RADDR(buf_b1, SRC_BUF_B1);
    `SPAN_FEATURE_RADDR(buf_b2, SRC_BUF_B2);
    `SPAN_FEATURE_RADDR(buf_b3, SRC_BUF_B3);
    `SPAN_FEATURE_RADDR(buf_c0, SRC_BUF_C0);
    `SPAN_FEATURE_RADDR(buf_c1, SRC_BUF_C1);
    `SPAN_FEATURE_RADDR(buf_c2, SRC_BUF_C2);
    `SPAN_FEATURE_RADDR(buf_c3, SRC_BUF_C3);
    `SPAN_FEATURE_RADDR(buf_d0, SRC_BUF_D0);
    `SPAN_FEATURE_RADDR(buf_d1, SRC_BUF_D1);
    `SPAN_FEATURE_RADDR(buf_d2, SRC_BUF_D2);
    `SPAN_FEATURE_RADDR(buf_d3, SRC_BUF_D3);
    `SPAN_FEATURE_RADDR(feat0_mem0, SRC_FEAT00);
    `SPAN_FEATURE_RADDR(feat0_mem1, SRC_FEAT01);
    `SPAN_FEATURE_RADDR(feat0_mem2, SRC_FEAT02);
    `SPAN_FEATURE_RADDR(feat0_mem3, SRC_FEAT03);
    `SPAN_FEATURE_RADDR(b1_mem0, SRC_B1_0);
    `SPAN_FEATURE_RADDR(b1_mem1, SRC_B1_1);
    `SPAN_FEATURE_RADDR(b1_mem2, SRC_B1_2);
    `SPAN_FEATURE_RADDR(b1_mem3, SRC_B1_3);
    `SPAN_FEATURE_RADDR(b5_2_mem0, SRC_B5_20);
    `SPAN_FEATURE_RADDR(b5_2_mem1, SRC_B5_21);
    `SPAN_FEATURE_RADDR(b5_2_mem2, SRC_B5_22);
    `SPAN_FEATURE_RADDR(b5_2_mem3, SRC_B5_23);
    `SPAN_FEATURE_RADDR(b6conv_mem0, SRC_B6_0);
    `SPAN_FEATURE_RADDR(b6conv_mem1, SRC_B6_1);
    `SPAN_FEATURE_RADDR(b6conv_mem2, SRC_B6_2);
    `SPAN_FEATURE_RADDR(b6conv_mem3, SRC_B6_3);

    `SPAN_INST_FEATURE_RAM(buf_a0);
    `SPAN_INST_FEATURE_RAM(buf_a1);
    `SPAN_INST_FEATURE_RAM(buf_a2);
    `SPAN_INST_FEATURE_RAM(buf_a3);
    `SPAN_INST_FEATURE_RAM(buf_b0);
    `SPAN_INST_FEATURE_RAM(buf_b1);
    `SPAN_INST_FEATURE_RAM(buf_b2);
    `SPAN_INST_FEATURE_RAM(buf_b3);
    `SPAN_INST_FEATURE_RAM(buf_c0);
    `SPAN_INST_FEATURE_RAM(buf_c1);
    `SPAN_INST_FEATURE_RAM(buf_c2);
    `SPAN_INST_FEATURE_RAM(buf_c3);
    `SPAN_INST_FEATURE_RAM(buf_d0);
    `SPAN_INST_FEATURE_RAM(buf_d1);
    `SPAN_INST_FEATURE_RAM(buf_d2);
    `SPAN_INST_FEATURE_RAM(buf_d3);
    `SPAN_INST_FEATURE_RAM(feat0_mem0);
    `SPAN_INST_FEATURE_RAM(feat0_mem1);
    `SPAN_INST_FEATURE_RAM(feat0_mem2);
    `SPAN_INST_FEATURE_RAM(feat0_mem3);
    `SPAN_INST_FEATURE_RAM(b1_mem0);
    `SPAN_INST_FEATURE_RAM(b1_mem1);
    `SPAN_INST_FEATURE_RAM(b1_mem2);
    `SPAN_INST_FEATURE_RAM(b1_mem3);
    `SPAN_INST_FEATURE_RAM(b5_2_mem0);
    `SPAN_INST_FEATURE_RAM(b5_2_mem1);
    `SPAN_INST_FEATURE_RAM(b5_2_mem2);
    `SPAN_INST_FEATURE_RAM(b5_2_mem3);
    `SPAN_INST_FEATURE_RAM(b6conv_mem0);
    `SPAN_INST_FEATURE_RAM(b6conv_mem1);
    `SPAN_INST_FEATURE_RAM(b6conv_mem2);
    `SPAN_INST_FEATURE_RAM(b6conv_mem3);

    span_sync_ram_1r1w #(
        .DATA_W(8),
        .DEPTH(UP_PIXEL_RAM_DEPTH),
        .ADDR_W(UP_PIXEL_ADDR_W)
    ) u_up_r_ram (
        .clk(clk),
        .we(up_r_we),
        .waddr(up_r_waddr),
        .wdata(up_r_wdata),
        .raddr(up_r_raddr),
        .rdata(up_r_rdata)
    );

    span_sync_ram_1r1w #(
        .DATA_W(8),
        .DEPTH(UP_PIXEL_RAM_DEPTH),
        .ADDR_W(UP_PIXEL_ADDR_W)
    ) u_up_g_ram (
        .clk(clk),
        .we(up_g_we),
        .waddr(up_g_waddr),
        .wdata(up_g_wdata),
        .raddr(up_g_raddr),
        .rdata(up_g_rdata)
    );

    span_sync_ram_1r1w #(
        .DATA_W(8),
        .DEPTH(UP_PIXEL_RAM_DEPTH),
        .ADDR_W(UP_PIXEL_ADDR_W)
    ) u_up_b_ram (
        .clk(clk),
        .we(up_b_we),
        .waddr(up_b_waddr),
        .wdata(up_b_wdata),
        .raddr(up_b_raddr),
        .rdata(up_b_rdata)
    );
`ifndef SYNTHESIS
    reg signed [7:0] buf_c [0:FRAME_PIXELS*CH-1];
    reg signed [7:0] feat0_mem [0:FRAME_PIXELS*CH-1];
    reg signed [7:0] b1_mem [0:FRAME_PIXELS*CH-1];
    reg signed [7:0] b5_2_mem [0:FRAME_PIXELS*CH-1];
    reg signed [7:0] b6conv_mem [0:FRAME_PIXELS*CH-1];
    reg signed [7:0] dbg_b1_c1_raw [0:FRAME_PIXELS*CH-1];
    reg signed [7:0] dbg_b1_c1_act [0:FRAME_PIXELS*CH-1];
    reg signed [7:0] dbg_b1_c2_raw [0:FRAME_PIXELS*CH-1];
    reg signed [7:0] dbg_b1_c2_act [0:FRAME_PIXELS*CH-1];
    reg signed [7:0] dbg_b1_c3_raw [0:FRAME_PIXELS*CH-1];
    reg signed [7:0] dbg_b1_residual [0:FRAME_PIXELS*CH-1];
`endif

    reg [FRAME_W-1:0] wr_idx;
    reg [FRAME_W-1:0] pix_idx;
    reg [HR_FRAME_W-1:0] out_idx;
    reg [4:0] op_idx;
    reg [7:0] out_ch_idx;
    reg [TAP_W-1:0] tap_idx;
    reg block_in_sel;
    reg signed [ACC_W-1:0] acc_q;
    reg signed [7:0] act_q;
    reg signed [7:0] residual_q;

    wire take_in = s_valid && s_ready;
    wire take_out = m_valid && m_ready;
    wire capture_done = take_in && (wr_idx == FRAME_PIXELS-1);

    assign s_ready = (state == ST_CAPTURE);
    assign m_user = (state == ST_OUTPUT) && (out_idx == {HR_FRAME_W{1'b0}});
    assign m_last = (state == ST_OUTPUT) && ((out_idx % HR_W) == HR_W-1);

    wire [4:0] layer_id = op_to_layer(op_idx);
    wire [15:0] weight_addr = calc_weight_addr(op_idx, out_ch_idx, tap_idx);
    wire [7:0] bias_addr = out_ch_idx;
    wire signed [7:0] weight_i;
    wire signed [7:0] bias_i;

    span_official_weight_bank #(
        .CH(CH),
        .SCALE(SCALE),
        .SYNC_READ(1)
    ) u_weight_bank (
        .clk         (clk),
        .layer_id    (layer_id),
        .weight_addr (weight_addr),
        .bias_addr   (bias_addr),
        .weight_o    (weight_i),
        .bias_o      (bias_i)
    );

    reg signed [7:0] act_i;
    reg signed [7:0] residual_i;

    always @(*) begin
        case (act_rd_src)
            SRC_ZERO:   act_i = 8'sd0;
            SRC_RGB_R:  act_i = act_q;
            SRC_RGB_G:  act_i = act_q;
            SRC_RGB_B:  act_i = act_q;
            SRC_BUF_A0: act_i = buf_a0_rdata;
            SRC_BUF_A1: act_i = buf_a1_rdata;
            SRC_BUF_A2: act_i = buf_a2_rdata;
            SRC_BUF_A3: act_i = buf_a3_rdata;
            SRC_BUF_B0: act_i = buf_b0_rdata;
            SRC_BUF_B1: act_i = buf_b1_rdata;
            SRC_BUF_B2: act_i = buf_b2_rdata;
            SRC_BUF_B3: act_i = buf_b3_rdata;
            SRC_BUF_C0: act_i = buf_c0_rdata;
            SRC_BUF_C1: act_i = buf_c1_rdata;
            SRC_BUF_C2: act_i = buf_c2_rdata;
            SRC_BUF_C3: act_i = buf_c3_rdata;
            SRC_BUF_D0: act_i = buf_d0_rdata;
            SRC_BUF_D1: act_i = buf_d1_rdata;
            SRC_BUF_D2: act_i = buf_d2_rdata;
            SRC_BUF_D3: act_i = buf_d3_rdata;
            SRC_FEAT00: act_i = feat0_mem0_rdata;
            SRC_FEAT01: act_i = feat0_mem1_rdata;
            SRC_FEAT02: act_i = feat0_mem2_rdata;
            SRC_FEAT03: act_i = feat0_mem3_rdata;
            SRC_B1_0:   act_i = b1_mem0_rdata;
            SRC_B1_1:   act_i = b1_mem1_rdata;
            SRC_B1_2:   act_i = b1_mem2_rdata;
            SRC_B1_3:   act_i = b1_mem3_rdata;
            SRC_B5_20:  act_i = b5_2_mem0_rdata;
            SRC_B5_21:  act_i = b5_2_mem1_rdata;
            SRC_B5_22:  act_i = b5_2_mem2_rdata;
            SRC_B5_23:  act_i = b5_2_mem3_rdata;
            SRC_B6_0:   act_i = b6conv_mem0_rdata;
            SRC_B6_1:   act_i = b6conv_mem1_rdata;
            SRC_B6_2:   act_i = b6conv_mem2_rdata;
            SRC_B6_3:   act_i = b6conv_mem3_rdata;
            default:    act_i = 8'sd0;
        endcase

        case (residual_rd_src)
            SRC_ZERO:   residual_i = 8'sd0;
            SRC_RGB_R:  residual_i = 8'sd0;
            SRC_RGB_G:  residual_i = 8'sd0;
            SRC_RGB_B:  residual_i = 8'sd0;
            SRC_BUF_A0: residual_i = buf_a0_rdata;
            SRC_BUF_A1: residual_i = buf_a1_rdata;
            SRC_BUF_A2: residual_i = buf_a2_rdata;
            SRC_BUF_A3: residual_i = buf_a3_rdata;
            SRC_BUF_B0: residual_i = buf_b0_rdata;
            SRC_BUF_B1: residual_i = buf_b1_rdata;
            SRC_BUF_B2: residual_i = buf_b2_rdata;
            SRC_BUF_B3: residual_i = buf_b3_rdata;
            SRC_BUF_C0: residual_i = buf_c0_rdata;
            SRC_BUF_C1: residual_i = buf_c1_rdata;
            SRC_BUF_C2: residual_i = buf_c2_rdata;
            SRC_BUF_C3: residual_i = buf_c3_rdata;
            SRC_BUF_D0: residual_i = buf_d0_rdata;
            SRC_BUF_D1: residual_i = buf_d1_rdata;
            SRC_BUF_D2: residual_i = buf_d2_rdata;
            SRC_BUF_D3: residual_i = buf_d3_rdata;
            SRC_FEAT00: residual_i = feat0_mem0_rdata;
            SRC_FEAT01: residual_i = feat0_mem1_rdata;
            SRC_FEAT02: residual_i = feat0_mem2_rdata;
            SRC_FEAT03: residual_i = feat0_mem3_rdata;
            SRC_B1_0:   residual_i = b1_mem0_rdata;
            SRC_B1_1:   residual_i = b1_mem1_rdata;
            SRC_B1_2:   residual_i = b1_mem2_rdata;
            SRC_B1_3:   residual_i = b1_mem3_rdata;
            SRC_B5_20:  residual_i = b5_2_mem0_rdata;
            SRC_B5_21:  residual_i = b5_2_mem1_rdata;
            SRC_B5_22:  residual_i = b5_2_mem2_rdata;
            SRC_B5_23:  residual_i = b5_2_mem3_rdata;
            SRC_B6_0:   residual_i = b6conv_mem0_rdata;
            SRC_B6_1:   residual_i = b6conv_mem1_rdata;
            SRC_B6_2:   residual_i = b6conv_mem2_rdata;
            SRC_B6_3:   residual_i = b6conv_mem3_rdata;
            default:    residual_i = 8'sd0;
        endcase
    end
    wire signed [15:0] product = act_i * weight_i;
    wire signed [ACC_W-1:0] product_ext = {{(ACC_W-16){product[15]}}, product};
    wire signed [ACC_W-1:0] acc_next = acc_q + product_ext;
    wire signed [7:0] q_raw = requant8(acc_next);
    wire signed [7:0] q_store = postprocess_output(op_idx, pix_idx, out_ch_idx, q_raw);
    wire last_tap = (tap_idx == tap_count_for_op(op_idx)-1);

    function [4:0] op_to_layer;
        input [4:0] op;
        begin
            case (op)
                5'd0: op_to_layer = 5'd0;
                5'd1: op_to_layer = 5'd1;
                5'd2: op_to_layer = 5'd2;
                5'd3: op_to_layer = 5'd3;
                5'd4: op_to_layer = 5'd4;
                5'd5: op_to_layer = 5'd5;
                5'd6: op_to_layer = 5'd6;
                5'd7: op_to_layer = 5'd7;
                5'd8: op_to_layer = 5'd8;
                5'd9: op_to_layer = 5'd9;
                5'd10: op_to_layer = 5'd10;
                5'd11: op_to_layer = 5'd11;
                5'd12: op_to_layer = 5'd12;
                5'd13: op_to_layer = 5'd13;
                5'd14: op_to_layer = 5'd14;
                5'd15: op_to_layer = 5'd15;
                5'd16: op_to_layer = 5'd16;
                5'd17: op_to_layer = 5'd17;
                5'd18: op_to_layer = 5'd18;
                5'd19: op_to_layer = 5'd19;
                5'd20: op_to_layer = 5'd20;
                default: op_to_layer = 5'd21;
            endcase
        end
    endfunction

    function integer in_ch_for_op;
        input [4:0] op;
        begin
            if (op == 5'd0)
                in_ch_for_op = 3;
            else if (op == 5'd20)
                in_ch_for_op = CH * 4;
            else
                in_ch_for_op = CH;
        end
    endfunction

    function integer out_ch_for_op;
        input [4:0] op;
        begin
            if (op == 5'd21)
                out_ch_for_op = UP_CH;
            else
                out_ch_for_op = CH;
        end
    endfunction

    function integer tap_count_for_op;
        input [4:0] op;
        begin
            if (op == 5'd20)
                tap_count_for_op = CH * 4;
            else
                tap_count_for_op = in_ch_for_op(op) * 9;
        end
    endfunction

    function [15:0] calc_weight_addr;
        input [4:0] op;
        input [7:0] out_ch;
        input [TAP_W-1:0] tap;
        begin
            if (op == 5'd20)
                calc_weight_addr = out_ch * (CH * 4) + tap;
            else
                calc_weight_addr = out_ch * tap_count_for_op(op) + tap;
        end
    endfunction

    function signed [7:0] sat8;
        input signed [31:0] value;
        begin
            if (value > 127)
                sat8 = 8'sd127;
            else if (value < -128)
                sat8 = 8'sh80;
            else
                sat8 = value[7:0];
        end
    endfunction

    function signed [7:0] requant8;
        input signed [ACC_W-1:0] value;
        reg signed [ACC_W-1:0] scaled;
        begin
            scaled = value >>> SCALE_SHIFT;
            if (scaled > 127)
                requant8 = 8'sd127;
            else if (scaled < -128)
                requant8 = 8'sh80;
            else
                requant8 = scaled[7:0];
        end
    endfunction

    function [7:0] sigmoid_u8_approx;
        input signed [7:0] x;
        integer x_i;
        integer gate_i;
        begin
            x_i = $signed(x);
            gate_i = (x_i >>> 1) + 128;
            if (gate_i < 0)
                sigmoid_u8_approx = 8'd0;
            else if (gate_i > 255)
                sigmoid_u8_approx = 8'd255;
            else
                sigmoid_u8_approx = gate_i[7:0];
        end
    endfunction

    function signed [7:0] silu8;
        input signed [7:0] x;
        integer x_i;
        integer gate_i;
        integer scaled_i;
        begin
            // 使用 integer 完成有符号乘法，避免拼接表达式把负数按无符号处理。
            x_i = $signed(x);
            gate_i = sigmoid_u8_approx(x);
            scaled_i = (x_i * gate_i) >>> 8;
            silu8 = sat8(scaled_i);
        end
    endfunction

    function signed [7:0] spab_attention8;
        input signed [7:0] out3;
        input signed [7:0] residual;
        integer sigmoid_i;
        integer gate_i;
        integer sum_i;
        reg signed [31:0] prod_i;
        integer scaled_i;
        begin
            // SPAB 注意力：(out3 + residual) * (sigmoid(out3) - 0.5)。
            sigmoid_i = {1'b0, sigmoid_u8_approx(out3)};
            gate_i = sigmoid_i - 128;
            sum_i = $signed(out3) + $signed(residual);
            prod_i = sum_i * gate_i;
            scaled_i = prod_i >>> 8;
            spab_attention8 = sat8(scaled_i);
        end
    endfunction

    function integer feature_bank_addr;
        input integer addr;
        integer pix;
        integer ch;
        begin
            pix = addr / CH;
            ch = addr % CH;
            feature_bank_addr = pix * FEATURE_BANK_CH + (ch % FEATURE_BANK_CH);
        end
    endfunction

    function integer feature_bank_sel;
        input integer addr;
        integer ch;
        begin
            ch = addr % CH;
            feature_bank_sel = ch / FEATURE_BANK_CH;
        end
    endfunction

    function [37:0] make_feature_req;
        input [3:0] group;
        input integer addr;
        integer bank;
        integer baddr;
        reg [5:0] src;
        begin
            bank = feature_bank_sel(addr);
            baddr = feature_bank_addr(addr);
            src = SRC_ZERO;
            case (group)
                GROUP_BUF_A: begin
                    case (bank)
                        0: src = SRC_BUF_A0;
                        1: src = SRC_BUF_A1;
                        2: src = SRC_BUF_A2;
                        default: src = SRC_BUF_A3;
                    endcase
                end
                GROUP_BUF_B: begin
                    case (bank)
                        0: src = SRC_BUF_B0;
                        1: src = SRC_BUF_B1;
                        2: src = SRC_BUF_B2;
                        default: src = SRC_BUF_B3;
                    endcase
                end
                GROUP_BUF_C: begin
                    case (bank)
                        0: src = SRC_BUF_C0;
                        1: src = SRC_BUF_C1;
                        2: src = SRC_BUF_C2;
                        default: src = SRC_BUF_C3;
                    endcase
                end
                GROUP_BUF_D: begin
                    case (bank)
                        0: src = SRC_BUF_D0;
                        1: src = SRC_BUF_D1;
                        2: src = SRC_BUF_D2;
                        default: src = SRC_BUF_D3;
                    endcase
                end
                GROUP_FEAT0: begin
                    case (bank)
                        0: src = SRC_FEAT00;
                        1: src = SRC_FEAT01;
                        2: src = SRC_FEAT02;
                        default: src = SRC_FEAT03;
                    endcase
                end
                GROUP_B1: begin
                    case (bank)
                        0: src = SRC_B1_0;
                        1: src = SRC_B1_1;
                        2: src = SRC_B1_2;
                        default: src = SRC_B1_3;
                    endcase
                end
                GROUP_B5_2: begin
                    case (bank)
                        0: src = SRC_B5_20;
                        1: src = SRC_B5_21;
                        2: src = SRC_B5_22;
                        default: src = SRC_B5_23;
                    endcase
                end
                GROUP_B6: begin
                    case (bank)
                        0: src = SRC_B6_0;
                        1: src = SRC_B6_1;
                        2: src = SRC_B6_2;
                        default: src = SRC_B6_3;
                    endcase
                end
                default: src = SRC_ZERO;
            endcase
            make_feature_req = {src, baddr[31:0]};
        end
    endfunction

    function [37:0] make_pingpong_req;
        input sel;
        input integer addr;
        begin
            if (sel)
                make_pingpong_req = make_feature_req(GROUP_BUF_B, addr);
            else
                make_pingpong_req = make_feature_req(GROUP_BUF_A, addr);
        end
    endfunction

    function [37:0] make_cat_req;
        input integer src_pix;
        input integer ch;
        integer addr;
        begin
            addr = src_pix * CH + (ch % CH);
            if (ch < CH)
                make_cat_req = make_feature_req(GROUP_FEAT0, addr);
            else if (ch < CH*2)
                make_cat_req = make_feature_req(GROUP_B6, addr);
            else if (ch < CH*3)
                make_cat_req = make_feature_req(GROUP_B1, addr);
            else
                make_cat_req = make_feature_req(GROUP_B5_2, addr);
        end
    endfunction

    function [37:0] make_spatial_req;
        input [4:0] op;
        input integer src_pix;
        input integer ch;
        integer addr;
        begin
            addr = src_pix * CH + ch;
            if (op == 5'd0) begin
                case (ch)
                    0: make_spatial_req = {SRC_RGB_R, src_pix[31:0]};
                    1: make_spatial_req = {SRC_RGB_G, src_pix[31:0]};
                    default: make_spatial_req = {SRC_RGB_B, src_pix[31:0]};
                endcase
            end else if (op == 5'd21) begin
                make_spatial_req = make_feature_req(GROUP_BUF_C, addr);
            end else if (op == 5'd19) begin
                make_spatial_req = make_pingpong_req(block_in_sel, addr);
            end else if ((op == 5'd1) || (op == 5'd4) || (op == 5'd7) ||
                         (op == 5'd10) || (op == 5'd13) || (op == 5'd16)) begin
                make_spatial_req = make_pingpong_req(block_in_sel, addr);
            end else if ((op == 5'd2) || (op == 5'd5) || (op == 5'd8) ||
                          (op == 5'd11) || (op == 5'd14) || (op == 5'd17)) begin
                make_spatial_req = make_feature_req(GROUP_BUF_C, addr);
            end else begin
                make_spatial_req = make_feature_req(GROUP_BUF_D, addr);
            end
        end
    endfunction

    function [37:0] make_activation_req;
        input [4:0] op;
        input [FRAME_W-1:0] pix;
        input [TAP_W-1:0] tap;
        integer x;
        integer y;
        integer kx;
        integer ky;
        integer sx;
        integer sy;
        integer src_pix;
        integer ch;
        begin
            if (op == 5'd20) begin
                make_activation_req = make_cat_req(pix, tap);
            end else begin
                ch = tap / 9;
                kx = tap % 3;
                ky = (tap / 3) % 3;
                x = pix % IMG_W;
                y = pix / IMG_W;
                sx = x + kx - 1;
                sy = y + ky - 1;
                if ((sx < 0) || (sx >= IMG_W) || (sy < 0) || (sy >= IMG_H)) begin
                    make_activation_req = {SRC_ZERO, 32'd0};
                end else begin
                    src_pix = sy * IMG_W + sx;
                    make_activation_req = make_spatial_req(op, src_pix, ch);
                end
            end
        end
    endfunction

    function [37:0] make_residual_req;
        input [4:0] op;
        input [FRAME_W-1:0] pix;
        input [7:0] out_ch;
        integer addr;
        begin
            addr = pix * CH + out_ch;
            if ((op == 5'd3) || (op == 5'd6) || (op == 5'd9) ||
                (op == 5'd12) || (op == 5'd15) || (op == 5'd18))
                make_residual_req = make_pingpong_req(block_in_sel, addr);
            else
                make_residual_req = {SRC_ZERO, 32'd0};
        end
    endfunction

    function signed [7:0] postprocess_output;
        input [4:0] op;
        input [FRAME_W-1:0] pix;
        input [7:0] out_ch;
        input signed [7:0] q;
        reg signed [7:0] residual;
        begin
            if ((op == 5'd1) || (op == 5'd2) || (op == 5'd4) || (op == 5'd5) ||
                (op == 5'd7) || (op == 5'd8) || (op == 5'd10) || (op == 5'd11) ||
                (op == 5'd13) || (op == 5'd14) || (op == 5'd16) || (op == 5'd17)) begin
                postprocess_output = silu8(q);
            end else if ((op == 5'd3) || (op == 5'd6) || (op == 5'd9) ||
                         (op == 5'd12) || (op == 5'd15) || (op == 5'd18)) begin
                residual = residual_i;
                postprocess_output = spab_attention8(q, residual);
            end else begin
                postprocess_output = q;
            end
        end
    endfunction

    task request_activation_read;
        input [4:0] op;
        input [FRAME_W-1:0] pix;
        input [TAP_W-1:0] tap;
        reg [37:0] req;
        begin
            req = make_activation_req(op, pix, tap);
            act_rd_src  <= req[37:32];
            act_rd_addr <= req[31:0];
        end
    endtask

    task request_residual_read;
        input [4:0] op;
        input [FRAME_W-1:0] pix;
        input [7:0] out_ch;
        reg [37:0] req;
        begin
            req = make_residual_req(op, pix, out_ch);
            residual_rd_src  <= req[37:32];
            residual_rd_addr <= req[31:0];
        end
    endtask

    task request_output_read;
        input [HR_FRAME_W-1:0] hr_idx;
        integer hx;
        integer hy;
        integer lx;
        integer ly;
        integer sub_x;
        integer sub_y;
        integer sub;
        integer lr_pix;
        integer out_addr;
        begin
            hx = hr_idx % HR_W;
            hy = hr_idx / HR_W;
            lx = hx / SCALE;
            ly = hy / SCALE;
            sub_x = hx % SCALE;
            sub_y = hy % SCALE;
            sub = sub_y * SCALE + sub_x;
            lr_pix = ly * IMG_W + lx;
            out_addr = lr_pix * UP_SUBPIXELS + sub;
            up_r_raddr <= out_addr[UP_PIXEL_ADDR_W-1:0];
            up_g_raddr <= out_addr[UP_PIXEL_ADDR_W-1:0];
            up_b_raddr <= out_addr[UP_PIXEL_ADDR_W-1:0];
        end
    endtask

    task clear_feature_ram_writes;
        begin
            buf_a0_we <= 1'b0; buf_a1_we <= 1'b0; buf_a2_we <= 1'b0; buf_a3_we <= 1'b0;
            buf_b0_we <= 1'b0; buf_b1_we <= 1'b0; buf_b2_we <= 1'b0; buf_b3_we <= 1'b0;
            buf_c0_we <= 1'b0; buf_c1_we <= 1'b0; buf_c2_we <= 1'b0; buf_c3_we <= 1'b0;
            buf_d0_we <= 1'b0; buf_d1_we <= 1'b0; buf_d2_we <= 1'b0; buf_d3_we <= 1'b0;
            feat0_mem0_we <= 1'b0; feat0_mem1_we <= 1'b0; feat0_mem2_we <= 1'b0; feat0_mem3_we <= 1'b0;
            b1_mem0_we <= 1'b0; b1_mem1_we <= 1'b0; b1_mem2_we <= 1'b0; b1_mem3_we <= 1'b0;
            b5_2_mem0_we <= 1'b0; b5_2_mem1_we <= 1'b0; b5_2_mem2_we <= 1'b0; b5_2_mem3_we <= 1'b0;
            b6conv_mem0_we <= 1'b0; b6conv_mem1_we <= 1'b0; b6conv_mem2_we <= 1'b0; b6conv_mem3_we <= 1'b0;
            up_r_we <= 1'b0; up_g_we <= 1'b0; up_b_we <= 1'b0;
        end
    endtask

    task write_up_mem;
        input [FRAME_W-1:0] pix;
        input [7:0] out_ch;
        input signed [7:0] value;
        integer sub;
        integer color;
        integer out_addr;
        begin
            // Match PyTorch PixelShuffle: input channel = color * SCALE*SCALE + subpixel.
            color = out_ch / UP_SUBPIXELS;
            sub = out_ch % UP_SUBPIXELS;
            out_addr = pix * UP_SUBPIXELS + sub;
            case (color)
                0: begin up_r_we <= 1'b1; up_r_waddr <= out_addr[UP_PIXEL_ADDR_W-1:0]; up_r_wdata <= value; end
                1: begin up_g_we <= 1'b1; up_g_waddr <= out_addr[UP_PIXEL_ADDR_W-1:0]; up_g_wdata <= value; end
                default: begin up_b_we <= 1'b1; up_b_waddr <= out_addr[UP_PIXEL_ADDR_W-1:0]; up_b_wdata <= value; end
            endcase
        end
    endtask

    task write_buf_a;
        input integer addr;
        input signed [7:0] value;
        integer bank;
        integer baddr;
        begin
            bank = feature_bank_sel(addr);
            baddr = feature_bank_addr(addr);
            case (bank)
                0: begin buf_a0_we <= 1'b1; buf_a0_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_a0_wdata <= value; end
                1: begin buf_a1_we <= 1'b1; buf_a1_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_a1_wdata <= value; end
                2: begin buf_a2_we <= 1'b1; buf_a2_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_a2_wdata <= value; end
                default: begin buf_a3_we <= 1'b1; buf_a3_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_a3_wdata <= value; end
            endcase
        end
    endtask

    task write_buf_b;
        input integer addr;
        input signed [7:0] value;
        integer bank;
        integer baddr;
        begin
            bank = feature_bank_sel(addr);
            baddr = feature_bank_addr(addr);
            case (bank)
                0: begin buf_b0_we <= 1'b1; buf_b0_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_b0_wdata <= value; end
                1: begin buf_b1_we <= 1'b1; buf_b1_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_b1_wdata <= value; end
                2: begin buf_b2_we <= 1'b1; buf_b2_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_b2_wdata <= value; end
                default: begin buf_b3_we <= 1'b1; buf_b3_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_b3_wdata <= value; end
            endcase
        end
    endtask

    task write_buf_c;
        input integer addr;
        input signed [7:0] value;
        integer bank;
        integer baddr;
        begin
            bank = feature_bank_sel(addr);
            baddr = feature_bank_addr(addr);
            case (bank)
                0: begin buf_c0_we <= 1'b1; buf_c0_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_c0_wdata <= value; end
                1: begin buf_c1_we <= 1'b1; buf_c1_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_c1_wdata <= value; end
                2: begin buf_c2_we <= 1'b1; buf_c2_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_c2_wdata <= value; end
                default: begin buf_c3_we <= 1'b1; buf_c3_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_c3_wdata <= value; end
            endcase
`ifndef SYNTHESIS
            buf_c[addr] <= value;
`endif
        end
    endtask

    task write_buf_d;
        input integer addr;
        input signed [7:0] value;
        integer bank;
        integer baddr;
        begin
            bank = feature_bank_sel(addr);
            baddr = feature_bank_addr(addr);
            case (bank)
                0: begin buf_d0_we <= 1'b1; buf_d0_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_d0_wdata <= value; end
                1: begin buf_d1_we <= 1'b1; buf_d1_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_d1_wdata <= value; end
                2: begin buf_d2_we <= 1'b1; buf_d2_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_d2_wdata <= value; end
                default: begin buf_d3_we <= 1'b1; buf_d3_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; buf_d3_wdata <= value; end
            endcase
        end
    endtask

    task write_feat0_mem;
        input integer addr;
        input signed [7:0] value;
        integer bank;
        integer baddr;
        begin
            bank = feature_bank_sel(addr);
            baddr = feature_bank_addr(addr);
            case (bank)
                0: begin feat0_mem0_we <= 1'b1; feat0_mem0_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; feat0_mem0_wdata <= value; end
                1: begin feat0_mem1_we <= 1'b1; feat0_mem1_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; feat0_mem1_wdata <= value; end
                2: begin feat0_mem2_we <= 1'b1; feat0_mem2_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; feat0_mem2_wdata <= value; end
                default: begin feat0_mem3_we <= 1'b1; feat0_mem3_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; feat0_mem3_wdata <= value; end
            endcase
`ifndef SYNTHESIS
            feat0_mem[addr] <= value;
`endif
        end
    endtask

    task write_b1_mem;
        input integer addr;
        input signed [7:0] value;
        integer bank;
        integer baddr;
        begin
            bank = feature_bank_sel(addr);
            baddr = feature_bank_addr(addr);
            case (bank)
                0: begin b1_mem0_we <= 1'b1; b1_mem0_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; b1_mem0_wdata <= value; end
                1: begin b1_mem1_we <= 1'b1; b1_mem1_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; b1_mem1_wdata <= value; end
                2: begin b1_mem2_we <= 1'b1; b1_mem2_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; b1_mem2_wdata <= value; end
                default: begin b1_mem3_we <= 1'b1; b1_mem3_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; b1_mem3_wdata <= value; end
            endcase
`ifndef SYNTHESIS
            b1_mem[addr] <= value;
`endif
        end
    endtask

    task write_b5_2_mem;
        input integer addr;
        input signed [7:0] value;
        integer bank;
        integer baddr;
        begin
            bank = feature_bank_sel(addr);
            baddr = feature_bank_addr(addr);
            case (bank)
                0: begin b5_2_mem0_we <= 1'b1; b5_2_mem0_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; b5_2_mem0_wdata <= value; end
                1: begin b5_2_mem1_we <= 1'b1; b5_2_mem1_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; b5_2_mem1_wdata <= value; end
                2: begin b5_2_mem2_we <= 1'b1; b5_2_mem2_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; b5_2_mem2_wdata <= value; end
                default: begin b5_2_mem3_we <= 1'b1; b5_2_mem3_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; b5_2_mem3_wdata <= value; end
            endcase
`ifndef SYNTHESIS
            b5_2_mem[addr] <= value;
`endif
        end
    endtask

    task write_b6conv_mem;
        input integer addr;
        input signed [7:0] value;
        integer bank;
        integer baddr;
        begin
            bank = feature_bank_sel(addr);
            baddr = feature_bank_addr(addr);
            case (bank)
                0: begin b6conv_mem0_we <= 1'b1; b6conv_mem0_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; b6conv_mem0_wdata <= value; end
                1: begin b6conv_mem1_we <= 1'b1; b6conv_mem1_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; b6conv_mem1_wdata <= value; end
                2: begin b6conv_mem2_we <= 1'b1; b6conv_mem2_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; b6conv_mem2_wdata <= value; end
                default: begin b6conv_mem3_we <= 1'b1; b6conv_mem3_waddr <= baddr[FEATURE_BANK_ADDR_W-1:0]; b6conv_mem3_wdata <= value; end
            endcase
`ifndef SYNTHESIS
            b6conv_mem[addr] <= value;
`endif
        end
    endtask

    task store_output_value;
        input [4:0] op;
        input [FRAME_W-1:0] pix;
        input [7:0] out_ch;
        input signed [7:0] raw_q;
        input signed [7:0] value_q;
        integer addr;
        reg signed [7:0] value_calc;
        begin
            addr = pix * CH + out_ch;
            value_calc = postprocess_output(op, pix, out_ch, raw_q);
            if (op == 5'd0) begin
                write_buf_a(addr, value_calc);
                write_feat0_mem(addr, value_calc);
            end else if ((op == 5'd1) || (op == 5'd4) || (op == 5'd7) ||
                         (op == 5'd10) || (op == 5'd13) || (op == 5'd16)) begin
                write_buf_c(addr, value_calc);
`ifndef SYNTHESIS
                if (op == 5'd1) begin
                    dbg_b1_c1_raw[addr] <= raw_q;
                    dbg_b1_c1_act[addr] <= value_calc;
                end
`endif
                if (op == 5'd16)
                    write_b5_2_mem(addr, raw_q);
            end else if ((op == 5'd2) || (op == 5'd5) || (op == 5'd8) ||
                         (op == 5'd11) || (op == 5'd14) || (op == 5'd17)) begin
                write_buf_d(addr, value_calc);
`ifndef SYNTHESIS
                if (op == 5'd2) begin
                    dbg_b1_c2_raw[addr] <= raw_q;
                    dbg_b1_c2_act[addr] <= value_calc;
                end
`endif
            end else if ((op == 5'd3) || (op == 5'd6) || (op == 5'd9) ||
                         (op == 5'd12) || (op == 5'd15) || (op == 5'd18)) begin
                if (block_in_sel)
                    write_buf_a(addr, value_calc);
                else
                    write_buf_b(addr, value_calc);
                if (op == 5'd3) begin
`ifndef SYNTHESIS
                    dbg_b1_c3_raw[addr] <= raw_q;
                    dbg_b1_residual[addr] <= residual_i;
`endif
                    write_b1_mem(addr, value_calc);
                end
            end else if (op == 5'd19) begin
                write_b6conv_mem(addr, value_calc);
            end else if (op == 5'd20) begin
                write_buf_c(addr, value_calc);
            end else if (op == 5'd21) begin
                write_up_mem(pix, out_ch, value_calc);
            end
        end
    endtask

    task advance_after_store;
        begin
            if (out_ch_idx == out_ch_for_op(op_idx)-1) begin
                out_ch_idx <= 8'd0;
                if (pix_idx == FRAME_PIXELS-1) begin
                    pix_idx <= {FRAME_W{1'b0}};
                    if ((op_idx == 5'd3) || (op_idx == 5'd6) || (op_idx == 5'd9) ||
                        (op_idx == 5'd12) || (op_idx == 5'd15) || (op_idx == 5'd18))
                        block_in_sel <= !block_in_sel;
                    if (op_idx == 5'd21) begin
                        request_output_read({HR_FRAME_W{1'b0}});
                        state <= ST_OUTPUT_WAIT;
                        out_idx <= {HR_FRAME_W{1'b0}};
                        m_valid <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        op_idx <= op_idx + 1'b1;
                        state <= ST_PREP;
                    end
                end else begin
                    pix_idx <= pix_idx + 1'b1;
                    state <= ST_PREP;
                end
            end else begin
                out_ch_idx <= out_ch_idx + 1'b1;
                state <= ST_PREP;
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            act_q      <= 8'sd0;
            residual_q <= 8'sd0;
        end else begin
            case (act_rd_src)
                SRC_RGB_R:  act_q <= $signed(rgb_mem[act_rd_addr][23:16]);
                SRC_RGB_G:  act_q <= $signed(rgb_mem[act_rd_addr][15:8]);
                SRC_RGB_B:  act_q <= $signed(rgb_mem[act_rd_addr][7:0]);
                default:    act_q <= 8'sd0;
            endcase

            residual_q <= residual_i;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state        <= ST_CAPTURE;
            wr_idx       <= {FRAME_W{1'b0}};
            pix_idx      <= {FRAME_W{1'b0}};
            out_idx      <= {HR_FRAME_W{1'b0}};
            op_idx       <= 5'd0;
            out_ch_idx   <= 8'd0;
            tap_idx      <= {TAP_W{1'b0}};
            block_in_sel <= 1'b0;
            acc_q        <= {ACC_W{1'b0}};
            act_rd_src   <= SRC_ZERO;
            act_rd_addr  <= 32'd0;
            residual_rd_src  <= SRC_ZERO;
            residual_rd_addr <= 32'd0;
            up_r_waddr   <= {UP_PIXEL_ADDR_W{1'b0}};
            up_g_waddr   <= {UP_PIXEL_ADDR_W{1'b0}};
            up_b_waddr   <= {UP_PIXEL_ADDR_W{1'b0}};
            up_r_raddr   <= {UP_PIXEL_ADDR_W{1'b0}};
            up_g_raddr   <= {UP_PIXEL_ADDR_W{1'b0}};
            up_b_raddr   <= {UP_PIXEL_ADDR_W{1'b0}};
            up_r_wdata   <= 8'sd0;
            up_g_wdata   <= 8'sd0;
            up_b_wdata   <= 8'sd0;
            m_valid      <= 1'b0;
            m_data       <= {DATA_W{1'b0}};
            busy         <= 1'b0;
            done         <= 1'b0;
            clear_feature_ram_writes();
        end else begin
            done <= 1'b0;
            clear_feature_ram_writes();

            case (state)
                ST_CAPTURE: begin
                    m_valid <= 1'b0;
                    busy <= 1'b0;
                    if (take_in) begin
                        rgb_mem[wr_idx] <= s_data;
                        if (capture_done) begin
                            wr_idx       <= {FRAME_W{1'b0}};
                            pix_idx      <= {FRAME_W{1'b0}};
                            op_idx       <= 5'd0;
                            out_ch_idx   <= 8'd0;
                            tap_idx      <= {TAP_W{1'b0}};
                            block_in_sel <= 1'b0;
                            busy         <= 1'b1;
                            request_activation_read(5'd0, {FRAME_W{1'b0}}, {TAP_W{1'b0}});
                            request_residual_read(5'd0, {FRAME_W{1'b0}}, 8'd0);
                            state        <= ST_PREP;
                        end else begin
                            wr_idx <= wr_idx + 1'b1;
                        end
                    end
                end

                ST_PREP: begin
                    busy    <= 1'b1;
                    tap_idx <= {TAP_W{1'b0}};
                    acc_q   <= {{(ACC_W-8){bias_i[7]}}, bias_i};
                    request_activation_read(op_idx, pix_idx, {TAP_W{1'b0}});
                    request_residual_read(op_idx, pix_idx, out_ch_idx);
                    // 同步权重 ROM 和特征 RAM 均有读延迟，先发 tap0 地址，再等待数据稳定。
                    state   <= ST_WEIGHT_WAIT;
                    state   <= ST_WEIGHT_WAIT;
                end

                ST_WEIGHT_WAIT: begin
                    busy  <= 1'b1;
                    state <= ST_DATA_WAIT;
                end

                ST_DATA_WAIT: begin
                    busy  <= 1'b1;
                    state <= ST_MAC;
                end

                ST_MAC: begin
                    acc_q <= acc_next;
                    if (last_tap) begin
                        store_output_value(op_idx, pix_idx, out_ch_idx, q_raw, q_store);
                        advance_after_store();
                    end else begin
                        request_activation_read(op_idx, pix_idx, tap_idx + 1'b1);
                        tap_idx <= tap_idx + 1'b1;
                        state   <= ST_WEIGHT_WAIT;
                    end
                end

                ST_OUTPUT_WAIT: begin
                    busy    <= 1'b0;
                    state   <= ST_OUTPUT_DATA;
                end

                ST_OUTPUT_DATA: begin
                    busy    <= 1'b0;
                    m_data  <= {up_r_rdata[7:0], up_g_rdata[7:0], up_b_rdata[7:0]};
                    m_valid <= 1'b1;
                    state   <= ST_OUTPUT;
                end

                ST_OUTPUT: begin
                    busy <= 1'b0;
                    if (take_out) begin
                        if (out_idx == HR_PIXELS-1) begin
                            m_valid <= 1'b0;
                            out_idx <= {HR_FRAME_W{1'b0}};
                            state   <= ST_CAPTURE;
                        end else begin
                            out_idx <= out_idx + 1'b1;
                            request_output_read(out_idx + 1'b1);
                            m_valid <= 1'b0;
                            state   <= ST_OUTPUT_WAIT;
                        end
                    end
                end

                default: state <= ST_CAPTURE;
            endcase
        end
    end

    wire unused_input_flags = s_user | s_last;
endmodule
