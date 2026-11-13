// Independent 50 MHz domain: synchronized PCIe state and a live counter.
module board_status (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK", X_INTERFACE_PARAMETER = "FREQ_HZ 50000000" *)
    input wire clk,
    input wire link_up,
    input wire pcie_resetn,
    input wire dma_resetn,
    input wire [2:0] leds,
    output wire [31:0] status,
    output wire resetn
);
    (* ASYNC_REG = "TRUE" *) reg [2:0] sync1 = 0, sync2 = 0;
    reg [23:0] ticks = 0;
    reg [7:0] startup = 0;
    always @(posedge clk) begin
        sync1 <= {dma_resetn, pcie_resetn, link_up};
        sync2 <= sync1;
        ticks <= ticks + 1'b1;
        if (!(&startup)) startup <= startup + 1'b1;
    end
    assign resetn = &startup;
    assign status = {8'hC7, ticks[23:6], leds, sync2};
endmodule
