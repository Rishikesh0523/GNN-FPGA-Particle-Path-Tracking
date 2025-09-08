`timescale 1ns / 1ps

// ============================================
// MULTIPLIER MODULE
// ============================================
module multiplier
#(
    parameter DATA_BITS   = 8,
    parameter WEIGHT_BITS = 8
)
(
    input  clk,
    input  rstn,
    // input  [31:0] counter,
    input  signed [WEIGHT_BITS-1:0] w,
    input  signed [DATA_BITS-1:0] x,
    output reg signed [DATA_BITS+WEIGHT_BITS-1:0] mult_result
);

always @(posedge clk or negedge rstn) begin
    if (!rstn)
        mult_result <= {(DATA_BITS+WEIGHT_BITS){1'b0}};
    else
        mult_result <= w * x;
end

endmodule