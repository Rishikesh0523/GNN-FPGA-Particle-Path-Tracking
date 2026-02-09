`timescale 1ns / 1ps
// Edge_Network: edge encoder + 8 MP edge blocks + edge decoder.
// Skeleton — block instantiations to be filled in.
module Edge_Network
#(
    parameter DATA_BITS = 8,
    parameter NUM_EDGES = 32,
    parameter FEATURE_DIM = 32
)
(
    input clk,
    input rstn,
    input start,
    input  [DATA_BITS*FEATURE_DIM*NUM_EDGES-1:0] edge_features_in,
    output                                       done,
    output [DATA_BITS*FEATURE_DIM*NUM_EDGES-1:0] edge_features_out
);
    // TODO: instantiate encoder + MP + decoder
    assign edge_features_out = edge_features_in;
    assign done              = 1'b0;
endmodule
