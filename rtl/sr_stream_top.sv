`timescale 1ns/1ps

module sr_stream_top #(
    parameter int DATA_W = 24,
    parameter int IMG_W  = 64,
    parameter int SCALE  = 2
) (
    input  logic              aclk,
    input  logic              aresetn,

    input  logic              s_axis_tvalid,
    output logic              s_axis_tready,
    input  logic [DATA_W-1:0] s_axis_tdata,
    input  logic              s_axis_tuser,
    input  logic              s_axis_tlast,

    output logic              m_axis_tvalid,
    input  logic              m_axis_tready,
    output logic [DATA_W-1:0] m_axis_tdata,
    output logic              m_axis_tuser,
    output logic              m_axis_tlast
);
    logic rst;
    logic mid_valid;
    logic mid_ready;
    logic [DATA_W-1:0] mid_data;
    logic mid_user;
    logic mid_last;

    assign rst = !aresetn;

    sr_residual_enhancer #(
        .DATA_W(DATA_W),
        .IMG_W (IMG_W)
    ) u_enhancer (
        .clk     (aclk),
        .rst     (rst),
        .s_valid (s_axis_tvalid),
        .s_ready (s_axis_tready),
        .s_data  (s_axis_tdata),
        .s_user  (s_axis_tuser),
        .s_last  (s_axis_tlast),
        .m_valid (mid_valid),
        .m_ready (mid_ready),
        .m_data  (mid_data),
        .m_user  (mid_user),
        .m_last  (mid_last)
    );

    sr_nearest_upsampler #(
        .DATA_W(DATA_W),
        .SCALE (SCALE)
    ) u_upsampler (
        .clk     (aclk),
        .rst     (rst),
        .s_valid (mid_valid),
        .s_ready (mid_ready),
        .s_data  (mid_data),
        .s_user  (mid_user),
        .s_last  (mid_last),
        .m_valid (m_axis_tvalid),
        .m_ready (m_axis_tready),
        .m_data  (m_axis_tdata),
        .m_user  (m_axis_tuser),
        .m_last  (m_axis_tlast)
    );
endmodule
