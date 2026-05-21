`timescale 1ns/1ps

module sr_nearest_upsampler #(
    parameter int DATA_W = 24,
    parameter int SCALE  = 2
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
    localparam int S_W = (SCALE <= 2) ? 1 : $clog2(SCALE);

    logic [DATA_W-1:0] pix_q;
    logic              user_q;
    logic              last_q;
    logic [S_W-1:0]    sx;
    logic [S_W-1:0]    sy;
    logic              busy;

    assign s_ready = !busy;
    assign m_valid = busy;
    assign m_data  = pix_q;
    assign m_user  = user_q && (sx == '0) && (sy == '0);
    assign m_last  = last_q && (sx == SCALE-1);

    wire take_in  = s_valid && s_ready;
    wire take_out = m_valid && m_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            pix_q  <= '0;
            user_q <= 1'b0;
            last_q <= 1'b0;
            sx     <= '0;
            sy     <= '0;
            busy   <= 1'b0;
        end else begin
            if (take_in) begin
                pix_q  <= s_data;
                user_q <= s_user;
                last_q <= s_last;
                sx     <= '0;
                sy     <= '0;
                busy   <= 1'b1;
            end else if (take_out) begin
                if ((sx == SCALE-1) && (sy == SCALE-1)) begin
                    busy <= 1'b0;
                    sx   <= '0;
                    sy   <= '0;
                end else if (sx == SCALE-1) begin
                    sx <= '0;
                    sy <= sy + 1'b1;
                end else begin
                    sx <= sx + 1'b1;
                end
            end
        end
    end
endmodule
