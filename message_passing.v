`timescale 1ns / 1ps
// Message passing block: edge -> aggregate -> node update, repeated per layer.
// Initial cut: top-level port list + per-layer instantiation stubs.
module message_passing
#(
    parameter DATA_BITS   = 8,
    parameter NUM_NODES   = 16,
    parameter NUM_EDGES   = 32,
    parameter FEATURE_DIM = 32
)
(
    input clk,
    input rstn,
    input start,
    // Connectivity (src/dst node indices per edge)
    input  [$clog2(NUM_NODES)*NUM_EDGES-1:0] src_idx_flat,
    input  [$clog2(NUM_NODES)*NUM_EDGES-1:0] dst_idx_flat,
    // Feature buffers (packed)
    input  [DATA_BITS*FEATURE_DIM*NUM_EDGES-1:0] edge_features_in,
    input  [DATA_BITS*FEATURE_DIM*NUM_NODES-1:0] node_features_in,
    output                                       done,
    output [DATA_BITS*FEATURE_DIM*NUM_EDGES-1:0] edge_features_out,
    output [DATA_BITS*FEATURE_DIM*NUM_NODES-1:0] node_features_out
);
    // TODO: instantiate MP_Edge_Layer_B0..7 + MP_Node_Layer_B0..7 via wrapper.
    assign edge_features_out = edge_features_in;
    assign node_features_out = node_features_in;
    assign done              = 1'b0;
endmodule
