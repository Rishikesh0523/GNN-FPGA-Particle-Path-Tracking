`timescale 1ns / 1ps

// Storage scratchpad.
// Houses BRAM-backed buffers for edge and node features plus
// (incoming) ping-pong buffers for streaming inference data.
// Connectivity tables (src/dst) will land here too.
module storage_module
#(
    parameter DATA_BITS = 8,
    parameter RAM_ADDR_BITS_FOR_NODE = 10,
    parameter RAM_ADDR_BITS_FOR_EDGE = 10,
    parameter NUM_NODES = 0,
    parameter NUM_EDGES = 0,
    parameter FEATURE_DIM = 32,
    parameter MAX_BURST_SIZE = 32
)
(
    input clk,
    input rst,

    // Encoder edge feature port
    input                                  enc_edge_we,
    input  [RAM_ADDR_BITS_FOR_EDGE-1:0]    enc_edge_addr,
    input  [DATA_BITS-1:0]                 enc_edge_din,
    output reg [DATA_BITS-1:0]             enc_edge_dout,

    // Encoder node feature port
    input                                  enc_node_we,
    input  [RAM_ADDR_BITS_FOR_NODE-1:0]    enc_node_addr,
    input  [DATA_BITS-1:0]                 enc_node_din,
    output reg [DATA_BITS-1:0]             enc_node_dout,

    // Connectivity src/dst (read-only, loaded from mem_files at init)
    input                                  src_re,
    input  [RAM_ADDR_BITS_FOR_EDGE-1:0]    src_addr,
    output [RAM_ADDR_BITS_FOR_NODE-1:0]    src_data,
    input                                  dst_re,
    input  [RAM_ADDR_BITS_FOR_EDGE-1:0]    dst_addr,
    output [RAM_ADDR_BITS_FOR_NODE-1:0]    dst_data
);

    wire [DATA_BITS-1:0] edge_raw, node_raw;

    bram_dual #(
        .RAM_WIDTH(DATA_BITS),
        .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_EDGE)
    ) u_edge_bram (
        .clock(clk),
        .we_a(enc_edge_we), .en_a(1'b1), .addr_a(enc_edge_addr), .din_a(enc_edge_din),
        .en_b(1'b1), .addr_b(enc_edge_addr), .dout_b(edge_raw)
    );

    bram_dual #(
        .RAM_WIDTH(DATA_BITS),
        .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_NODE)
    ) u_node_bram (
        .clock(clk),
        .we_a(enc_node_we), .en_a(1'b1), .addr_a(enc_node_addr), .din_a(enc_node_din),
        .en_b(1'b1), .addr_b(enc_node_addr), .dout_b(node_raw)
    );

    // Connectivity tables - initialized at elaboration time
    bram_dual #(
        .RAM_WIDTH(RAM_ADDR_BITS_FOR_NODE),
        .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_EDGE),
        .DATA_FILE("mem_files/connectivity_source_data.mem")
    ) u_src_bram (
        .clock(clk),
        .we_a(1'b0), .en_a(1'b0), .addr_a({RAM_ADDR_BITS_FOR_EDGE{1'b0}}),
        .din_a({RAM_ADDR_BITS_FOR_NODE{1'b0}}),
        .en_b(src_re), .addr_b(src_addr), .dout_b(src_data)
    );

    bram_dual #(
        .RAM_WIDTH(RAM_ADDR_BITS_FOR_NODE),
        .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_EDGE),
        .DATA_FILE("mem_files/connectivity_destination_data.mem")
    ) u_dst_bram (
        .clock(clk),
        .we_a(1'b0), .en_a(1'b0), .addr_a({RAM_ADDR_BITS_FOR_EDGE{1'b0}}),
        .din_a({RAM_ADDR_BITS_FOR_NODE{1'b0}}),
        .en_b(dst_re), .addr_b(dst_addr), .dout_b(dst_data)
    );

    always @(posedge clk) begin
        if (rst) begin
            enc_edge_dout <= {DATA_BITS{1'b0}};
            enc_node_dout <= {DATA_BITS{1'b0}};
        end else begin
            enc_edge_dout <= edge_raw;
            enc_node_dout <= node_raw;
        end
    end

endmodule
