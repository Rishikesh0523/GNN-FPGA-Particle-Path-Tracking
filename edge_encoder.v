`timescale 1ns / 1ps
// Edge encoder skeleton. Three-layer MLP over edge features.
// Detail will fill in once gen_encoder_layers.py is in place.
module edge_encoder
#(
    parameter DATA_BITS    = 8,
    parameter WEIGHT_BITS  = 8,
    parameter IN_DIM       = 8,
    parameter HIDDEN_DIM   = 32,
    parameter OUT_DIM      = 32,
    parameter NUM_EDGES    = 0
)
(
    input clk,
    input rstn,
    input start,
    input [DATA_BITS*IN_DIM-1:0] feature_in,
    output reg valid_out,
    output reg [DATA_BITS*OUT_DIM-1:0] feature_out
);
    // TODO: instantiate edge_encoder_layer_{1,2,3} once generator emits them.
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_out   <= 1'b0;
            feature_out <= {DATA_BITS*OUT_DIM{1'b0}};
        end
    end
endmodule
