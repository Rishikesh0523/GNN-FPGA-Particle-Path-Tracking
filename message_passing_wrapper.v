`timescale 1ns / 1ps
// Wrapper around the 8 message-passing blocks.
// Chains MP_Edge_Layer / MP_Node_Layer per block in sequence.
module message_passing_wrapper
#(
    parameter DATA_BITS   = 8,
    parameter NUM_NODES   = 16,
    parameter NUM_EDGES   = 32,
    parameter FEATURE_DIM = 32,
    parameter NUM_BLOCKS  = 8
)
(
    input clk,
    input rstn,
    input start,
    input  [DATA_BITS*FEATURE_DIM*NUM_EDGES-1:0] edge_features_in,
    input  [DATA_BITS*FEATURE_DIM*NUM_NODES-1:0] node_features_in,
    output                                       done,
    output [DATA_BITS*FEATURE_DIM*NUM_EDGES-1:0] edge_features_out,
    output [DATA_BITS*FEATURE_DIM*NUM_NODES-1:0] node_features_out
);
    // Block-chain will be instantiated once layers are validated.
    assign edge_features_out = edge_features_in;
    assign node_features_out = node_features_in;
    assign done              = 1'b0;
endmodule
