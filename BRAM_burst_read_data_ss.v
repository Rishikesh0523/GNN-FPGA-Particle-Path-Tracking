`timescale 1ns / 1ps
// Sequencer that drives bram_burst_wrapper for sustained encoder feeds.
// One outstanding burst at a time; raises done for one cycle on completion.
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
    output wire busy,
    output wire done,
    output wire [DATA_BITS*MAX_BURST_SIZE-1:0] data_out
);
    wire bw_done, bw_busy;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] bw_data;

    bram_burst_wrapper #(
        .DATA_BITS(DATA_BITS),
        .RAM_ADDR_BITS(RAM_ADDR_BITS),
        .MAX_BURST_SIZE(MAX_BURST_SIZE)
    ) u_burst (
        .clk(clk), .rst(rst),
        .start(start), .write_en(1'b0),
        .addr_base(addr_base),
        .burst_size(burst_size),
        .din_packed({DATA_BITS*MAX_BURST_SIZE{1'b0}}),
        .busy(bw_busy),
        .done(bw_done),
        .dout_packed(bw_data)
    );

    assign busy     = bw_busy;
    assign done     = bw_done;
    assign data_out = bw_data;
endmodule
