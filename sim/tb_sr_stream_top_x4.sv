`timescale 1ns/1ps

module tb_sr_stream_top_x4;
    localparam int DATA_W = 24;
    localparam int IMG_W  = 4;
    localparam int IMG_H  = 3;
    localparam int SCALE  = 4;
    localparam int OUT_BEATS = IMG_W * IMG_H * SCALE * SCALE;
    localparam int OUT_LINES = IMG_H * SCALE;

    logic clk = 1'b0;
    logic rstn = 1'b0;
    logic s_valid;
    logic s_ready;
    logic [DATA_W-1:0] s_data;
    logic s_user;
    logic s_last;
    logic m_valid;
    logic m_ready;
    logic [DATA_W-1:0] m_data;
    logic m_user;
    logic m_last;

    int in_x;
    int in_y;
    int out_count;
    int user_count;
    int last_count;
    int cyc;

    always #5 clk = ~clk;

    sr_stream_top #(
        .DATA_W(DATA_W),
        .IMG_W (IMG_W),
        .SCALE (SCALE)
    ) dut (
        .aclk          (clk),
        .aresetn       (rstn),
        .s_axis_tvalid (s_valid),
        .s_axis_tready (s_ready),
        .s_axis_tdata  (s_data),
        .s_axis_tuser  (s_user),
        .s_axis_tlast  (s_last),
        .m_axis_tvalid (m_valid),
        .m_axis_tready (m_ready),
        .m_axis_tdata  (m_data),
        .m_axis_tuser  (m_user),
        .m_axis_tlast  (m_last)
    );

    function automatic logic [23:0] pixel(input int x, input int y);
        logic [7:0] sx;
        logic [7:0] sy;
        logic [7:0] ss;
        begin
            sx = x[7:0];
            sy = y[7:0];
            ss = (x * 3 + y) & 8'hff;
            pixel = {sx, sy, ss};
        end
    endfunction

    always_comb begin
        s_valid = rstn && (in_y < IMG_H);
        s_data  = pixel(in_x, in_y);
        s_user  = (in_x == 0) && (in_y == 0);
        s_last  = (in_x == IMG_W-1);
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            in_x <= 0;
            in_y <= 0;
        end else if (s_valid && s_ready) begin
            if (in_x == IMG_W-1) begin
                in_x <= 0;
                in_y <= in_y + 1;
            end else begin
                in_x <= in_x + 1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            out_count  <= 0;
            user_count <= 0;
            last_count <= 0;
        end else if (m_valid && m_ready) begin
            out_count <= out_count + 1;
            if (m_user)
                user_count <= user_count + 1;
            if (m_last)
                last_count <= last_count + 1;
        end
    end

    initial begin
        m_ready = 1'b0;
        repeat (8) @(posedge clk);
        rstn = 1'b1;

        for (cyc = 0; cyc < 4000; cyc++) begin
            @(posedge clk);
            m_ready = (cyc % 11) != 5;
            if (out_count == OUT_BEATS)
                break;
        end

        repeat (10) @(posedge clk);
        if (out_count != OUT_BEATS)
            $fatal(1, "x4 output beat count mismatch: got %0d expected %0d", out_count, OUT_BEATS);
        if (user_count != 1)
            $fatal(1, "x4 SOF count mismatch: got %0d expected 1", user_count);
        if (last_count != OUT_LINES)
            $fatal(1, "x4 EOL count mismatch: got %0d expected %0d", last_count, OUT_LINES);
        $display("PASS sr_stream_top_x4: out=%0d sof=%0d eol=%0d", out_count, user_count, last_count);
        $finish;
    end
endmodule
