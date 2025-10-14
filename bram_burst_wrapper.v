`timescale 1ns / 1ps
// Initial burst wrapper around bram_dual.
// Issues a sequence of single-cycle reads/writes for a fixed burst length.
module bram_burst_wrapper #(
    parameter DATA_BITS       = 8,
    parameter RAM_ADDR_BITS   = 12,
    parameter MAX_BURST_SIZE  = 32
)(
    input clk,
    input rst,
    input start,
    input write_en,
    input [RAM_ADDR_BITS-1:0]               addr_base,
    input [$clog2(MAX_BURST_SIZE):0]        burst_size,
    input [DATA_BITS*MAX_BURST_SIZE-1:0]    din_packed,
    output reg                              busy,
    output reg                              done,
    output reg [DATA_BITS*MAX_BURST_SIZE-1:0] dout_packed
);
    // TODO: implement burst FSM; current placeholder ties outputs low.
    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            dout_packed <= {DATA_BITS*MAX_BURST_SIZE{1'b0}};
        end
    end
endmodule
