`timescale 1ns/1ps

module sr_residual_enhancer #(
    parameter int DATA_W = 24,
    parameter int IMG_W  = 64
) (
    input  logic              clk,
    input  logic              rst,

    input  logic              s_valid,
    output logic              s_ready,
    input  logic [DATA_W-1:0] s_data,
    input  logic              s_user,
    input  logic              s_last,

    output logic              m_valid,
    input  logic              m_ready,
    output logic [DATA_W-1:0] m_data,
    output logic              m_user,
    output logic              m_last
);
    localparam int CH_W = DATA_W / 3;
    localparam int X_W  = (IMG_W <= 2) ? 1 : $clog2(IMG_W);

    logic [DATA_W-1:0] line0 [0:IMG_W-1];
    logic [DATA_W-1:0] line1 [0:IMG_W-1];
    logic [DATA_W-1:0] left0;
    logic [DATA_W-1:0] left1;
    logic [X_W-1:0]    x_pos;
    logic              first_row;
    logic              second_row;

    logic              out_valid;
    logic [DATA_W-1:0] out_data;
    logic              out_user;
    logic              out_last;

    assign s_ready = !out_valid || m_ready;
    assign m_valid = out_valid;
    assign m_data  = out_data;
    assign m_user  = out_user;
    assign m_last  = out_last;

    function automatic logic [CH_W-1:0] clamp_u8(input logic signed [15:0] v);
        begin
            if (v < 0)
                clamp_u8 = '0;
            else if (v > ((1 << CH_W) - 1))
                clamp_u8 = {CH_W{1'b1}};
            else
                clamp_u8 = v[CH_W-1:0];
        end
    endfunction

    function automatic logic [DATA_W-1:0] enhance_pixel(
        input logic [DATA_W-1:0] cur,
        input logic [DATA_W-1:0] up,
        input logic [DATA_W-1:0] left,
        input logic              bypass
    );
        logic [CH_W-1:0] c [0:2];
        logic [CH_W-1:0] u [0:2];
        logic [CH_W-1:0] l [0:2];
        logic signed [15:0] avg;
        logic signed [15:0] detail;
        logic signed [15:0] value;
        int i;
        begin
            for (i = 0; i < 3; i++) begin
                c[i] = cur[i*CH_W +: CH_W];
                u[i] = up[i*CH_W +: CH_W];
                l[i] = left[i*CH_W +: CH_W];
                if (bypass) begin
                    enhance_pixel[i*CH_W +: CH_W] = c[i];
                end else begin
                    avg    = ($signed({1'b0, u[i]}) + $signed({1'b0, l[i]})) >>> 1;
                    detail = $signed({1'b0, c[i]}) - avg;
                    value  = $signed({1'b0, c[i]}) + (detail >>> 1);
                    enhance_pixel[i*CH_W +: CH_W] = clamp_u8(value);
                end
            end
        end
    endfunction

    wire fire = s_valid && s_ready;
    wire border = first_row || (x_pos == '0);

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid  <= 1'b0;
            out_data   <= '0;
            out_user   <= 1'b0;
            out_last   <= 1'b0;
            x_pos      <= '0;
            left0      <= '0;
            left1      <= '0;
            first_row  <= 1'b1;
            second_row <= 1'b1;
        end else begin
            if (m_ready)
                out_valid <= 1'b0;

            if (fire) begin
                out_valid <= 1'b1;
                out_user  <= s_user;
                out_last  <= s_last;
                out_data  <= enhance_pixel(s_data, line0[x_pos], left0, border);

                line1[x_pos] <= line0[x_pos];
                line0[x_pos] <= s_data;
                left1        <= line1[x_pos];
                left0        <= s_data;

                if (s_last) begin
                    x_pos     <= '0;
                    left0     <= '0;
                    left1     <= '0;
                    first_row <= 1'b0;
                    if (first_row)
                        second_row <= 1'b1;
                    else
                        second_row <= 1'b0;
                end else begin
                    x_pos <= x_pos + 1'b1;
                end
            end
        end
    end
endmodule
