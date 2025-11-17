`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// rms_norm_normalize.v
// RMSNorm normalization and scale:
//   y_i = (x_i * inv_rms) * gamma_i
//
// No mean subtraction (RMSNorm doesn't center), no beta.
// Otherwise identical pipeline to layer_norm_normalize.v.
//
// Latency: 2 cycles
//   Cycle 1: x * inv_rms  → norm[i]
//   Cycle 2: norm * gamma  → output
//------------------------------------------------------------------------------
module rms_norm_normalize #(
    parameter NUM_FEATURES       = 32,
    parameter DATA_BITS          = 24,
    parameter DATA_FRAC_BITS     = 10,
    parameter INV_SQRT_BITS      = 16,
    parameter INV_SQRT_FRAC_BITS = 11,
    parameter SCALE_BITS         = 8,
    parameter FRAC_BITS          = 6
)(
    input  clk,
    input  rstn,
    input  valid_in,

    input  signed [NUM_FEATURES*DATA_BITS-1:0]  data_in,
    input         [INV_SQRT_BITS-1:0]           inv_sqrt_in,

    input  signed [NUM_FEATURES*SCALE_BITS-1:0] gamma_flat,

    output reg valid_out,
    output reg signed [NUM_FEATURES*DATA_BITS-1:0] data_out
);
    wire signed [DATA_BITS-1:0]  x     [0:NUM_FEATURES-1];
    wire signed [SCALE_BITS-1:0] gamma [0:NUM_FEATURES-1];

    genvar k;
    generate
        for (k = 0; k < NUM_FEATURES; k = k + 1) begin : unpack
            assign x[k]     = data_in  [k*DATA_BITS   +: DATA_BITS];
            assign gamma[k] = gamma_flat[k*SCALE_BITS  +: SCALE_BITS];
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Stage 1: x * inv_rms
    //--------------------------------------------------------------------------
    localparam NORM_BITS = DATA_BITS + INV_SQRT_BITS;

    wire signed [NORM_BITS-1:0]  norm_full    [0:NUM_FEATURES-1];
    wire signed [DATA_BITS:0]    norm_shifted [0:NUM_FEATURES-1];

    generate
        for (k = 0; k < NUM_FEATURES; k = k + 1) begin : norm_mult
            assign norm_full[k]    = $signed(x[k]) * $signed({1'b0, inv_sqrt_in});
            assign norm_shifted[k] = norm_full[k] >>> INV_SQRT_FRAC_BITS;
        end
    endgenerate

    localparam signed [DATA_BITS-1:0] MAX_VAL = {1'b0, {(DATA_BITS-1){1'b1}}};
    localparam signed [DATA_BITS-1:0] MIN_VAL = {1'b1, {(DATA_BITS-1){1'b0}}};

    reg signed [DATA_BITS-1:0]  norm     [0:NUM_FEATURES-1];
    reg signed [SCALE_BITS-1:0] gamma_s1 [0:NUM_FEATURES-1];
    reg valid_s1;

    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_s1 <= 0;
            for (i = 0; i < NUM_FEATURES; i = i + 1) begin
                norm[i]     <= 0;
                gamma_s1[i] <= 0;
            end
        end else begin
            valid_s1 <= valid_in;
            for (i = 0; i < NUM_FEATURES; i = i + 1) begin
                if      (norm_shifted[i] > $signed({{1{1'b0}}, MAX_VAL})) norm[i] <= MAX_VAL;
                else if (norm_shifted[i] < $signed({{1{1'b1}}, MIN_VAL})) norm[i] <= MIN_VAL;
                else    norm[i] <= norm_shifted[i][DATA_BITS-1:0];
                gamma_s1[i] <= gamma[i];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Stage 2: norm * gamma
    //--------------------------------------------------------------------------
    localparam SCALED_BITS = DATA_BITS + SCALE_BITS;

    wire signed [SCALED_BITS-1:0] scaled       [0:NUM_FEATURES-1];
    wire signed [DATA_BITS:0]     scaled_shift  [0:NUM_FEATURES-1];

    generate
        for (k = 0; k < NUM_FEATURES; k = k + 1) begin : scale_shift
            assign scaled[k]      = $signed(norm[k]) * $signed(gamma_s1[k]);
            assign scaled_shift[k] = scaled[k][SCALED_BITS-1:FRAC_BITS];
        end
    endgenerate

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_out <= 0;
            data_out  <= 0;
        end else begin
            valid_out <= valid_s1;
            for (i = 0; i < NUM_FEATURES; i = i + 1) begin
                if      (scaled_shift[i] > $signed({{1{1'b0}}, MAX_VAL}))
                    data_out[i*DATA_BITS +: DATA_BITS] <= MAX_VAL;
                else if (scaled_shift[i] < $signed({{1{1'b1}}, MIN_VAL}))
                    data_out[i*DATA_BITS +: DATA_BITS] <= MIN_VAL;
                else
                    data_out[i*DATA_BITS +: DATA_BITS] <= scaled_shift[i][DATA_BITS-1:0];
            end
        end
    end

endmodule