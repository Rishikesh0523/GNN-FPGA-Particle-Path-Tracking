`timescale 1ns / 1ps
module adder
#(
    parameter DATA_BITS   = 8,
    parameter WEIGHT_BITS = 8,
    parameter ACCUM_EXTRA = 8                // extra bits for accumulator headroom
)
(
    input  clk,
    input  rstn,
    input  [31:0] counter,
    input  signed [DATA_BITS+WEIGHT_BITS-1:0] value_in,
    output reg signed [DATA_BITS+WEIGHT_BITS+ACCUM_EXTRA-1:0] value_out
);

    // Total accumulator bits
    localparam ACCUM_BITS = DATA_BITS + WEIGHT_BITS + ACCUM_EXTRA;

    // Internal accumulator
    reg signed [ACCUM_BITS-1:0] accumulator;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            accumulator <= {ACCUM_BITS{1'b0}};
            value_out   <= {ACCUM_BITS{1'b0}};
        end
        else if (counter == 1) begin
            // Start fresh accumulation
            accumulator <= {{ACCUM_EXTRA{value_in[DATA_BITS+WEIGHT_BITS-1]}}, value_in};
            value_out   <= {{ACCUM_EXTRA{value_in[DATA_BITS+WEIGHT_BITS-1]}}, value_in};
        end
        else if (counter >= 2) begin
            // Continue accumulating
            accumulator <= accumulator + {{ACCUM_EXTRA{value_in[DATA_BITS+WEIGHT_BITS-1]}}, value_in};
            value_out   <= accumulator;   // Output same width as accumulator
        end
        else begin
            // Counter 0 - hold zero
            accumulator <= {ACCUM_BITS{1'b0}};
            value_out   <= {ACCUM_BITS{1'b0}};
        end
    end

endmodule