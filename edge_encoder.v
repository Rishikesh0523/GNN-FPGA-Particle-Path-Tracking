`timescale 1ns / 1ps
// Edge encoder top: three stacked layers, each followed by layer norm.
// Currently runs over a single edge per pass; batching added later.
module edge_encoder
#(
    parameter DATA_BITS   = 8,
    parameter WEIGHT_BITS = 8,
    parameter IN_DIM      = 6,
    parameter HIDDEN_DIM  = 32,
    parameter OUT_DIM     = 32
)
(
    input clk,
    input rstn,
    input start,
    input [DATA_BITS*IN_DIM-1:0] feature_in,
    output valid_out,
    output [DATA_BITS*OUT_DIM-1:0] feature_out
);
    wire l1_done, l2_done, l3_done;
    wire [DATA_BITS*HIDDEN_DIM-1:0] l1_out, l2_out, l3_out;

    edge_encoder_layer_1 u_l1 (
        .clk(clk), .rstn(rstn), .start(start),
        .feature_in({{DATA_BITS*(HIDDEN_DIM-IN_DIM){1'b0}}, feature_in}),
        .done(l1_done), .feature_out(l1_out)
    );
    edge_encoder_layer_2 u_l2 (
        .clk(clk), .rstn(rstn), .start(l1_done),
        .feature_in(l1_out),
        .done(l2_done), .feature_out(l2_out)
    );
    edge_encoder_layer_3 u_l3 (
        .clk(clk), .rstn(rstn), .start(l2_done),
        .feature_in(l2_out),
        .done(l3_done), .feature_out(l3_out)
    );

    assign valid_out   = l3_done;
    assign feature_out = l3_out;
endmodule
