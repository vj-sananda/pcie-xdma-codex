`timescale 1ns/1ps
module tb_stream_fifo;
    reg clk = 0;
    always #2 clk = ~clk;
    reg resetn = 0;
    wire s_ready, m_valid;
    reg m_ready = 0;
    wire [127:0] m_data;
    wire [15:0] m_keep;
    wire m_last;
    integer sent = 0, received = 0, cycle = 0;
    integer stalls = 0;
    reg [31:0] rng = 32'hc7012026;
    localparam WORDS = 12000;
    wire s_valid = resetn && sent < WORDS;
    function [127:0] data_word(input integer n);
        data_word = {32'hC7DA7A00 ^ n, 32'hA55A1234 + n, ~n, n};
    endfunction
    function [15:0] keep_word(input integer n);
        keep_word = (n % 17 == 16) ? 16'h001f : 16'hffff;
    endfunction
    wire s_last = sent % 17 == 16 || sent == WORDS - 1;
    accelerator_stream_fifo_0 dut (
        .s_axis_aresetn(resetn), .s_axis_aclk(clk),
        .s_axis_tvalid(s_valid), .s_axis_tready(s_ready),
        .s_axis_tdata(data_word(sent)), .s_axis_tkeep(keep_word(sent)), .s_axis_tlast(s_last),
        .m_axis_tvalid(m_valid), .m_axis_tready(m_ready),
        .m_axis_tdata(m_data), .m_axis_tkeep(m_keep), .m_axis_tlast(m_last)
    );
    reg held = 0;
    reg [144:0] held_payload;
    always @(posedge clk) begin
        if (resetn) begin
            cycle <= cycle + 1;
            if (s_valid && s_ready) sent <= sent + 1;
            if (s_valid && !s_ready) stalls <= stalls + 1;
            if (held && (!m_valid || {m_data,m_keep,m_last} !== held_payload))
                $fatal(1, "Output changed while backpressured at word %0d", received);
            held <= m_valid && !m_ready;
            held_payload <= {m_data,m_keep,m_last};
            if (m_valid && m_ready) begin
                if (received >= sent) $fatal(1, "Unexpected output word");
                if (m_data !== data_word(received)) $fatal(1, "Data mismatch at %0d: actual=%032h expected=%032h sent=%0d", received, m_data, data_word(received), sent);
                if (m_keep !== keep_word(received)) $fatal(1, "TKEEP mismatch at %0d", received);
                if (m_last !== (received % 17 == 16 || received == WORDS - 1))
                    $fatal(1, "TLAST mismatch at %0d", received);
                received <= received + 1;
            end
        end
    end
    always @(negedge clk) begin
        rng = {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
        // First fill past capacity, then apply deterministic randomized stalls.
        m_ready = resetn && cycle >= 6000 && rng[2:0] != 0 && rng[5:3] != 0;
    end
    initial begin
        // Hold local reset well beyond the simulator's initial 100 ns global reset.
        repeat (100) @(negedge clk);
        resetn = 1;
        wait (received == WORDS);
        repeat (20) @(negedge clk);
        if (m_valid) $fatal(1, "FIFO emitted extra data");
        if (stalls < 1000) $fatal(1, "FIFO-full backpressure was not exercised");
        $display("FIFO_SIM_PASS: words=%0d bytes=%0d stalled_input_cycles=%0d; data/TKEEP/TLAST/stability checked", received, received*16, stalls);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "Simulation timeout");
    end
endmodule
