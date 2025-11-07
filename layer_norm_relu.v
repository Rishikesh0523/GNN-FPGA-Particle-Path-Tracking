`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// layer_norm_relu.v
// Post-processing module for layer norm output:
//   1. Optional ReLU: if act_en=1, zero out negative values
//   2. Requantize: Q14.10 (DATA_BITS=24) → Q4.4 (8-bit signed)
//      - Integer bits: 14 → 4  (drop upper integer bits, saturate)
//      - Frac bits:    10 → 4  (drop lower frac bits, truncate)
//      - Sign bit maintained
//
// Q14.10 layout (24 bits):  [23]=sign [22:10]=14 int bits [9:0]=10 frac bits
// Q4.4   layout  (8 bits):  [ 7]=sign  [6:3]= 4 int bits [3:0]= 4 frac bits
//
// Requantize:
//   Step 1: drop bottom (DATA_FRAC_BITS - OUT_FRAC_BITS) = 6 frac bits → shift right 6
//   Step 2: result is Q14.4 in 18 bits → saturate to Q4.4 in 8 bits
//
// Latency: 1 cycle
//------------------------------------------------------------------------------
module layer_norm_relu #(
    parameter NUM_FEATURES   = 32,
    parameter DATA_BITS      = 24,      // input width  Q14.10
    parameter DATA_FRAC_BITS = 10,      // input frac bits
    parameter OUT_BITS       = 8,       // output width Q4.4
    parameter OUT_FRAC_BITS  = 4,       // output frac bits
    parameter OUT_INT_BITS   = 3        // output integer bits (excl sign)
)(
    input  clk,
    input  rstn,

    input  valid_in,
    input  act_en,                                              // 1 = apply ReLU

    input  signed [NUM_FEATURES*DATA_BITS-1:0]    data_in,

    output reg valid_out,
    output reg signed [NUM_FEATURES*OUT_BITS-1:0] data_out
);

    // Number of fractional bits to drop
    localparam FRAC_DROP = DATA_FRAC_BITS - OUT_FRAC_BITS;     // 10 - 4 = 6

    // After dropping frac bits, width before saturation
    // Q14.10 >> 6  →  Q14.4  in (DATA_BITS - FRAC_DROP) = 18 bits
    localparam SHIFT_BITS = DATA_BITS - FRAC_DROP;              // 18

    // Saturation limits for Q4.4 signed (8-bit)
    // Max =  0111_1111 = 127  = +7.9375
    // Min =  1000_0000 = -128 = -8.0
    localparam signed [OUT_BITS-1:0] OUT_MAX =  {1'b0, {(OUT_BITS-1){1'b1}}};  //  127
    localparam signed [OUT_BITS-1:0] OUT_MIN =  {1'b1, {(OUT_BITS-1){1'b0}}};  // -128

    // Unpack input features
    wire signed [DATA_BITS-1:0] x [0:NUM_FEATURES-1];
    genvar k;
    generate
        for (k = 0; k < NUM_FEATURES; k = k + 1) begin : unpack
            assign x[k] = data_in[k*DATA_BITS +: DATA_BITS];
        end
    endgenerate

    // After arithmetic right shift by FRAC_DROP
    wire signed [SHIFT_BITS-1:0] shifted [0:NUM_FEATURES-1];
    generate
        for (k = 0; k < NUM_FEATURES; k = k + 1) begin : do_shift
            assign shifted[k] = $signed(x[k]) >>> FRAC_DROP;
        end
    endgenerate

    // After optional ReLU
    wire signed [SHIFT_BITS-1:0] after_relu [0:NUM_FEATURES-1];
    generate
        for (k = 0; k < NUM_FEATURES; k = k + 1) begin : do_relu
            assign after_relu[k] = (act_en && shifted[k][SHIFT_BITS-1])
                                   ? {SHIFT_BITS{1'b0}}   // negative → zero
                                   : shifted[k];
        end
    endgenerate

    // Register + saturate to OUT_BITS
    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_out <= 1'b0;
            data_out  <= {(NUM_FEATURES*OUT_BITS){1'b0}};
        end else begin
            valid_out <= valid_in;
            for (i = 0; i < NUM_FEATURES; i = i + 1) begin
                if (after_relu[i] > $signed({{(SHIFT_BITS-OUT_BITS){1'b0}}, OUT_MAX}))
                    data_out[i*OUT_BITS +: OUT_BITS] <= OUT_MAX;
                else if (after_relu[i] < $signed({{(SHIFT_BITS-OUT_BITS){1'b1}}, OUT_MIN}))
                    data_out[i*OUT_BITS +: OUT_BITS] <= OUT_MIN;
                else
                    data_out[i*OUT_BITS +: OUT_BITS] <= after_relu[i][OUT_BITS-1:0];
            end
        end
    end

endmodule
