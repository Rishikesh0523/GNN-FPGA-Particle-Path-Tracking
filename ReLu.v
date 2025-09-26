`timescale 1ns / 1ps
// Basic ReLU activation. Clamps negative values to zero on each cycle.
module ReLu
#(
    parameter DATA_BITS = 16
)
(
    input  signed [DATA_BITS-1:0] in,
    output signed [DATA_BITS-1:0] out
);
    assign out = (in[DATA_BITS-1]) ? {DATA_BITS{1'b0}} : in;
endmodule
