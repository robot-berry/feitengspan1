`timescale 1ns/1ps

// 单读单写同步 RAM。
// 用于完整官方 SPAN 帧级计算引擎中的特征缓存和输出缓存，
// 让 Vivado 按常规 FPGA RAM/BRAM 结构综合，而不是推成大规模寄存器和多路选择器。
module span_sync_ram_1r1w #(
    parameter integer DATA_W = 8,
    parameter integer DEPTH  = 1024,
    parameter integer ADDR_W = 10
) (
    input  wire                  clk,
    input  wire                  we,
    input  wire [ADDR_W-1:0]     waddr,
    input  wire signed [DATA_W-1:0] wdata,
    input  wire [ADDR_W-1:0]     raddr,
    output reg  signed [DATA_W-1:0] rdata
);
    generate
        if (DEPTH <= 4096) begin : g_flat_ram
            (* ram_style = "block" *) reg signed [DATA_W-1:0] mem [0:DEPTH-1];

            always @(posedge clk) begin
                if (we)
                    mem[waddr] <= wdata;
                rdata <= mem[raddr];
            end
        end else begin : g_banked_ram
            localparam integer BANK_DEPTH = 4096;
            localparam integer BANK_ADDR_W = 12;
            localparam integer BANKS = (DEPTH + BANK_DEPTH - 1) / BANK_DEPTH;
            localparam integer BANK_SEL_W = (BANKS <= 2) ? 1 : $clog2(BANKS);

            wire [BANK_ADDR_W-1:0] waddr_lo = waddr[BANK_ADDR_W-1:0];
            wire [BANK_ADDR_W-1:0] raddr_lo = raddr[BANK_ADDR_W-1:0];
            wire [BANK_SEL_W-1:0] wbank = waddr[ADDR_W-1:BANK_ADDR_W];
            wire [BANK_SEL_W-1:0] rbank = raddr[ADDR_W-1:BANK_ADDR_W];

            reg [BANK_SEL_W-1:0] rbank_q;
            reg signed [DATA_W-1:0] bank_rdata [0:BANKS-1];

            genvar bank_i;
            for (bank_i = 0; bank_i < BANKS; bank_i = bank_i + 1) begin : g_bank
                localparam [BANK_SEL_W-1:0] BANK_INDEX = bank_i[BANK_SEL_W-1:0];
                (* ram_style = "block" *) reg signed [DATA_W-1:0] mem [0:BANK_DEPTH-1];

                always @(posedge clk) begin
                    if (we && (wbank == BANK_INDEX))
                        mem[waddr_lo] <= wdata;
                    bank_rdata[bank_i] <= mem[raddr_lo];
                end
            end

            always @(posedge clk) begin
                rbank_q <= rbank;
            end

            always @(*) begin
                rdata = bank_rdata[rbank_q];
            end
        end
    endgenerate
endmodule
