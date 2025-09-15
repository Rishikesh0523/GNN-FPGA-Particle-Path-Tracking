`timescale 1ns / 1ps

// Initial storage scratchpad - dual BRAM array sketch.
// Wraps two bram_dual instances for edge/node feature buffering.
module storage_module
#(
    parameter DATA_BITS = 8,
    parameter RAM_ADDR_BITS_FOR_NODE = 10,
    parameter RAM_ADDR_BITS_FOR_EDGE = 10,
    parameter NUM_NODES = 0,
    parameter NUM_EDGES = 0
)
(
    input clk,
    input rst,
    input  [RAM_ADDR_BITS_FOR_EDGE-1:0] edge_addr,
    input  [RAM_ADDR_BITS_FOR_NODE-1:0] node_addr,
    input  edge_we,
    input  node_we,
    input  [DATA_BITS-1:0] edge_din,
    input  [DATA_BITS-1:0] node_din,
    output [DATA_BITS-1:0] edge_dout,
    output [DATA_BITS-1:0] node_dout
);

    bram_dual #(
        .RAM_WIDTH(DATA_BITS),
        .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_EDGE)
    ) u_edge_bram (
        .clock(clk),
        .we_a(edge_we), .en_a(1'b1), .addr_a(edge_addr), .din_a(edge_din),
        .en_b(1'b1), .addr_b(edge_addr), .dout_b(edge_dout)
    );

    bram_dual #(
        .RAM_WIDTH(DATA_BITS),
        .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_NODE)
    ) u_node_bram (
        .clock(clk),
        .we_a(node_we), .en_a(1'b1), .addr_a(node_addr), .din_a(node_din),
        .en_b(1'b1), .addr_b(node_addr), .dout_b(node_dout)
    );

endmodule
