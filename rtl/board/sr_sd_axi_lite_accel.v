`timescale 1ns/1ps

// SD 文件验证用 AXI-Lite 超分加速器。
// 板上 MicroSD 接在 Zynq PS 的 SD1/MIO 上，因此 SD 文件读写由 PS 软件完成；
// 本模块只负责提供一个 AXI-Lite 寄存器窗口，让 PS 把 RGB888 像素逐个送入
// sr_super_resolution_pipeline，并逐个读回放大后的 RGB888 像素。
//
// 该接口重在上板功能验证，吞吐量不如 AXI-DMA/VDMA，但工程简单、容易调通。
module sr_sd_axi_lite_accel #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer DATA_W             = 24,
    parameter integer IMG_W              = 64,
    parameter integer SCALE              = 2,
    parameter integer USE_FULL_OFFICIAL_SPAN = 0,
    parameter integer VIDEO_GAIN_EN      = 1
) (
    input  wire                              s_axi_aclk,
    input  wire                              s_axi_aresetn,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                        s_axi_awprot,
    input  wire                              s_axi_awvalid,
    output reg                               s_axi_awready,

    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output reg                               s_axi_wready,

    output reg  [1:0]                        s_axi_bresp,
    output reg                               s_axi_bvalid,
    input  wire                              s_axi_bready,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                        s_axi_arprot,
    input  wire                              s_axi_arvalid,
    output reg                               s_axi_arready,

    output reg  [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                        s_axi_rresp,
    output reg                               s_axi_rvalid,
    input  wire                              s_axi_rready,

    output wire                              irq
);
    localparam [5:0] REG_STATUS       = 6'h00;
    localparam [5:0] REG_INPUT_FLAGS  = 6'h04;
    localparam [5:0] REG_INPUT_PIXEL  = 6'h08;
    localparam [5:0] REG_OUTPUT_PIXEL = 6'h0c;
    localparam [5:0] REG_OUTPUT_FLAGS = 6'h10;
    localparam [5:0] REG_COUNTER_IN   = 6'h14;
    localparam [5:0] REG_COUNTER_OUT  = 6'h18;
    localparam [5:0] REG_ERROR        = 6'h1c;

    reg [C_S_AXI_ADDR_WIDTH-1:0] awaddr_reg;
    reg [C_S_AXI_ADDR_WIDTH-1:0] araddr_reg;

    reg        input_user_reg;
    reg        input_last_reg;
    reg        input_push;
    reg [23:0] input_pixel_reg;

    wire       in_ready;
    wire       out_valid;
    wire [23:0] out_pixel;
    wire       out_user;
    wire       out_last;

    reg        out_hold_valid;
    reg [23:0] out_hold_pixel;
    reg        out_hold_user;
    reg        out_hold_last;
    wire       write_accept;
    wire       read_accept;
    wire       out_pop_now;

    reg [31:0] input_count;
    reg [31:0] output_count;
    reg        input_drop_error;
    reg        output_overrun_error;

    wire rst = !s_axi_aresetn;
    assign write_accept = !s_axi_bvalid && s_axi_awvalid && s_axi_wvalid;
    assign read_accept  = !s_axi_rvalid && s_axi_arvalid;
    assign out_pop_now  = read_accept && (s_axi_araddr[5:0] == REG_OUTPUT_PIXEL) && out_hold_valid;

    wire can_capture_output = !out_hold_valid || out_pop_now;

    assign irq = out_hold_valid;

    // AXI-Lite 写通道：单拍接收地址和数据。
    always @(posedge s_axi_aclk) begin
        if (rst) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            awaddr_reg    <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;

            if (write_accept) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                awaddr_reg    <= s_axi_awaddr;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // AXI-Lite 读通道：读取状态/输出寄存器。
    always @(posedge s_axi_aclk) begin
        if (rst) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= {C_S_AXI_DATA_WIDTH{1'b0}};
            araddr_reg    <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            s_axi_arready <= 1'b0;
            if (read_accept) begin
                s_axi_arready <= 1'b1;
                araddr_reg    <= s_axi_araddr;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;
                case (s_axi_araddr[5:0])
                    REG_STATUS:
                        s_axi_rdata <= {
                            20'd0,
                            output_overrun_error,
                            input_drop_error,
                            out_hold_last,
                            out_hold_user,
                            out_hold_valid,
                            in_ready,
                            6'd0
                        };
                    REG_OUTPUT_PIXEL:
                        s_axi_rdata <= {8'd0, out_hold_pixel};
                    REG_OUTPUT_FLAGS:
                        s_axi_rdata <= {30'd0, out_hold_last, out_hold_user};
                    REG_COUNTER_IN:
                        s_axi_rdata <= input_count;
                    REG_COUNTER_OUT:
                        s_axi_rdata <= output_count;
                    REG_ERROR:
                        s_axi_rdata <= {30'd0, output_overrun_error, input_drop_error};
                    default:
                        s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    always @(posedge s_axi_aclk) begin
        if (rst) begin
            input_user_reg      <= 1'b0;
            input_last_reg      <= 1'b0;
            input_push          <= 1'b0;
            input_pixel_reg     <= 24'd0;
            input_count         <= 32'd0;
            input_drop_error    <= 1'b0;
        end else begin
            input_push <= 1'b0;
            if (write_accept) begin
                case (s_axi_awaddr[5:0])
                    REG_INPUT_FLAGS: begin
                        input_user_reg <= s_axi_wdata[0];
                        input_last_reg <= s_axi_wdata[1];
                    end
                    REG_INPUT_PIXEL: begin
                        if (in_ready) begin
                            input_pixel_reg  <= s_axi_wdata[23:0];
                            input_push       <= 1'b1;
                            input_count      <= input_count + 32'd1;
                        end else begin
                            input_drop_error <= 1'b1;
                        end
                    end
                    REG_ERROR: begin
                        if (s_axi_wdata[0])
                            input_drop_error <= 1'b0;
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

    always @(posedge s_axi_aclk) begin
        if (rst) begin
            out_hold_valid       <= 1'b0;
            out_hold_pixel       <= 24'd0;
            out_hold_user        <= 1'b0;
            out_hold_last        <= 1'b0;
            output_count         <= 32'd0;
            output_overrun_error <= 1'b0;
        end else begin
            if (out_valid && can_capture_output) begin
                out_hold_valid <= 1'b1;
                out_hold_pixel <= out_pixel;
                out_hold_user  <= out_user;
                out_hold_last  <= out_last;
                output_count   <= output_count + 32'd1;
            end else if (out_pop_now) begin
                out_hold_valid <= 1'b0;
            end

            if (write_accept && s_axi_awaddr[5:0] == REG_ERROR && s_axi_wdata[1])
                output_overrun_error <= 1'b0;
        end
    end

    sr_super_resolution_pipeline #(
        .DATA_W(DATA_W),
        .IMG_W (IMG_W),
        .SCALE (SCALE),
        .USE_FULL_OFFICIAL_SPAN(USE_FULL_OFFICIAL_SPAN),
        .VIDEO_GAIN_EN(VIDEO_GAIN_EN)
    ) u_sr_pipeline (
        .aclk          (s_axi_aclk),
        .aresetn       (s_axi_aresetn),
        .s_axis_tvalid (input_push),
        .s_axis_tready (in_ready),
        .s_axis_tdata  (input_pixel_reg),
        .s_axis_tuser  (input_user_reg),
        .s_axis_tlast  (input_last_reg),
        .m_axis_tvalid (out_valid),
        .m_axis_tready (can_capture_output),
        .m_axis_tdata  (out_pixel),
        .m_axis_tuser  (out_user),
        .m_axis_tlast  (out_last)
    );

    // 未使用的 AXI 保护/字节选通信号保留，避免综合器误报未连接端口语义。
    wire unused_axi = |s_axi_awprot | |s_axi_arprot | |s_axi_wstrb | |araddr_reg;
endmodule
