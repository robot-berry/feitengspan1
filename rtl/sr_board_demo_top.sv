`timescale 1ns/1ps

module sr_board_demo_top #(
    parameter int IMG_W = 32,
    parameter int IMG_H = 18,
    parameter int SCALE = 2
) (
    input  logic       diff_clock_rtl_0_clk_p,
    input  logic       diff_clock_rtl_0_clk_n,
    input  logic [0:0] sw_0,
    input  logic [0:0] sw_1,
    output logic [0:0] led_0,
    output logic [0:0] led_1,
    output logic [0:0] led_2,
    output logic [0:0] led_3,
    output logic [0:0] led_4,
    output logic [0:0] led_5,
    output logic [0:0] led_6,
    output logic [0:0] led_7
);
    logic clk;
    logic rstn;

`ifdef SIMULATION
    assign clk = diff_clock_rtl_0_clk_p;
`else
    IBUFDS u_clk_ibufds (
        .I (diff_clock_rtl_0_clk_p),
        .IB(diff_clock_rtl_0_clk_n),
        .O (clk)
    );
`endif

    logic [23:0] in_data;
    logic        in_valid;
    logic        in_ready;
    logic        in_user;
    logic        in_last;
    logic        out_valid;
    logic        out_ready;
    logic [23:0] out_data;
    logic        out_user;
    logic        out_last;

    logic [15:0] x_cnt;
    logic [15:0] y_cnt;
    logic [31:0] frame_crc;
    logic [23:0] beat_cnt;
    logic [23:0] rst_shift = '0;

    assign rstn      = rst_shift[23] && !sw_0[0];
    assign out_ready = 1'b1;
    assign in_valid  = rstn;
    assign in_user   = (x_cnt == 0) && (y_cnt == 0);
    assign in_last   = (x_cnt == IMG_W-1);
    assign in_data   = {x_cnt[7:0], y_cnt[7:0], x_cnt[7:0] ^ y_cnt[7:0]};

    always_ff @(posedge clk) begin
        rst_shift <= {rst_shift[22:0], 1'b1};
        if (!rstn) begin
            x_cnt <= '0;
            y_cnt <= '0;
        end else if (in_valid && in_ready) begin
            if (x_cnt == IMG_W-1) begin
                x_cnt <= '0;
                if (y_cnt == IMG_H-1)
                    y_cnt <= '0;
                else
                    y_cnt <= y_cnt + 1'b1;
            end else begin
                x_cnt <= x_cnt + 1'b1;
            end
        end
    end

    sr_stream_top #(
        .DATA_W(24),
        .IMG_W (IMG_W),
        .SCALE (SCALE)
    ) u_dut (
        .aclk          (clk),
        .aresetn       (rstn),
        .s_axis_tvalid (in_valid),
        .s_axis_tready (in_ready),
        .s_axis_tdata  (in_data),
        .s_axis_tuser  (in_user),
        .s_axis_tlast  (in_last),
        .m_axis_tvalid (out_valid),
        .m_axis_tready (out_ready),
        .m_axis_tdata  (out_data),
        .m_axis_tuser  (out_user),
        .m_axis_tlast  (out_last)
    );

    always_ff @(posedge clk) begin
        if (!rstn || out_user) begin
            frame_crc <= 32'h1ace_55aa;
            beat_cnt  <= '0;
        end else if (out_valid && out_ready) begin
            frame_crc <= {frame_crc[30:0], frame_crc[31]} ^ {8'h0, out_data};
            beat_cnt  <= beat_cnt + 1'b1;
        end
    end

    assign led_0[0] = rstn;
    assign led_1[0] = in_ready;
    assign led_2[0] = out_valid;
    assign led_3[0] = out_last;
    assign led_4[0] = sw_1[0] ? beat_cnt[16] : frame_crc[0];
    assign led_5[0] = sw_1[0] ? beat_cnt[17] : frame_crc[8];
    assign led_6[0] = sw_1[0] ? beat_cnt[18] : frame_crc[16];
    assign led_7[0] = sw_1[0] ? beat_cnt[19] : frame_crc[24];
endmodule
