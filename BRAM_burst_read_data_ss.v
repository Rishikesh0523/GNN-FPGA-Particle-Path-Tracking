`timescale 1ns / 1ps
// Sequencer that issues sustained burst reads from bram_burst_wrapper
// and forwards beats to the encoder pipeline.
// Initial cut: pipelined start/done handshake; data path tied off.
module BRAM_burst_read_data_ss #(
    parameter DATA_BITS      = 8,
    parameter RAM_ADDR_BITS  = 12,
    parameter MAX_BURST_SIZE = 32
)(
    input clk,
    input rst,
    input start,
    input [RAM_ADDR_BITS-1:0] addr_base,
    input [$clog2(MAX_BURST_SIZE):0] burst_size,
    output reg busy,
    output reg done,
    output reg [DATA_BITS*MAX_BURST_SIZE-1:0] data_out
);
    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            data_out <= {DATA_BITS*MAX_BURST_SIZE{1'b0}};
        end else if (start) begin
            busy <= 1'b1;
        end
    end
endmodule
