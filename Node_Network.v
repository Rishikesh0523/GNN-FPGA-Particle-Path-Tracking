`timescale 1ns / 1ps
// Node_Network: node encoder + MP node updates + readout.
// Skeleton — block instantiations to be filled in.
module Node_Network
#(
    parameter DATA_BITS   = 8,
    parameter NUM_NODES   = 16,
    parameter FEATURE_DIM = 32
)
(
    input clk,
    input rstn,
    input start,
    input  [DATA_BITS*FEATURE_DIM*NUM_NODES-1:0] node_features_in,
    output                                       done,
    output [DATA_BITS*FEATURE_DIM*NUM_NODES-1:0] node_features_out
);
    assign node_features_out = node_features_in;
    assign done              = 1'b0;
endmodule
