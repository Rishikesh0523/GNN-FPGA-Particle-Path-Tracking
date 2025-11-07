`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// layer_norm_normalize.v
// Applies normalization and learnable scale/shift:
//   y_i = ((x_i - mean) * inv_sqrt) * gamma_i + beta_i
//
// Processes all NUM_FEATURES in parallel (one DSP chain per feature).
//
// Latency: 3 cycles
//   Cycle 1: (x - mean) → diff
//   Cycle 2: diff * inv_sqrt → normalized (Q13.10 format)
//   Cycle 3: normalized * gamma + beta → output (re-quantized to DATA_BITS)
//
// Fixed-point:
//   x, mean, output : DATA_BITS signed
//   inv_sqrt        : OUT_BITS unsigned Q5.11
//   gamma, beta     : SCALE_BITS signed (Q(SCALE_BITS-FRAC_BITS).FRAC_BITS)
//   FRAC_BITS       : fractional bits in gamma/beta (default 7 for Q1.7)
//------------------------------------------------------------------------------
module layer_norm_normalize #(
    parameter NUM_FEATURES = 32,
    parameter DATA_BITS    = 24,
    parameter DATA_FRAC_BITS = 10,    // fractional bits in input data
    parameter INV_SQRT_BITS= 16,   // Q5.11
    parameter INV_SQRT_FRAC_BITS = 11,
    parameter SCALE_BITS   = 8,    // gamma/beta bit width
    parameter FRAC_BITS    = 6     // fractional bits in gamma/beta
)(
    input  clk,
    input  rstn,
    input  valid_in,

    input  signed [NUM_FEATURES*DATA_BITS-1:0]  data_in,
    input  signed [DATA_BITS-1:0]               mean_in,
    input         [INV_SQRT_BITS-1:0]           inv_sqrt_in,   // Q1.15 unsigned

    // Learnable parameters (loaded externally)
    input  signed [NUM_FEATURES*SCALE_BITS-1:0] gamma_flat,
    input  signed [NUM_FEATURES*SCALE_BITS-1:0] beta_flat,

    output reg valid_out,
    output reg signed [NUM_FEATURES*DATA_BITS-1:0] data_out
);

    // Unpack inputs
    wire signed [DATA_BITS-1:0]  x     [0:NUM_FEATURES-1];
    wire signed [SCALE_BITS-1:0] gamma [0:NUM_FEATURES-1];
    wire signed [SCALE_BITS-1:0] beta  [0:NUM_FEATURES-1];
    
    genvar k;
    generate
        for (k = 0; k < NUM_FEATURES; k = k + 1) begin : unpack
            assign x[k]     = data_in  [k*DATA_BITS  +: DATA_BITS];
            assign gamma[k] = gamma_flat[k*SCALE_BITS +: SCALE_BITS];
            assign beta[k]  = beta_flat [k*SCALE_BITS +: SCALE_BITS];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Stage 1: Subtract mean → diff[i] = x[i] - mean
    // -------------------------------------------------------------------------
    reg signed [DATA_BITS:0]      diff       [0:NUM_FEATURES-1];  // 9-bit
    reg        [INV_SQRT_BITS-1:0] inv_sqrt_s1;
    reg valid_s1;

    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_s1    <= 0;
            inv_sqrt_s1 <= 0;
            for (i = 0; i < NUM_FEATURES; i = i + 1) diff[i] <= 0;
        end else begin
            valid_s1    <= valid_in;
            inv_sqrt_s1 <= inv_sqrt_in;
            for (i = 0; i < NUM_FEATURES; i = i + 1)
                diff[i] <= {{1{x[i][DATA_BITS-1]}}, x[i]}
                         - {{1{mean_in[DATA_BITS-1]}}, mean_in};
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2: Multiply by inv_sqrt → norm[i] = diff[i] * inv_sqrt
    // diff is Q(DATA_BITS-DATA_FRAC_BITS+1).DATA_FRAC_BITS signed
    // inv_sqrt is Q5.11 unsigned
    // product is Q(DATA_BITS+2).15, shift right 15 to get Q(DATA_BITS+2).0
    // then truncate to DATA_BITS signed (clamp if needed)
    // -------------------------------------------------------------------------
    localparam NORM_BITS = DATA_BITS + 1 + INV_SQRT_BITS; // full product width

    reg signed [DATA_BITS-1:0]    norm       [0:NUM_FEATURES-1];
    reg signed [SCALE_BITS-1:0]   gamma_s2   [0:NUM_FEATURES-1];
    reg signed [SCALE_BITS-1:0]   beta_s2    [0:NUM_FEATURES-1];
    reg valid_s2;

    // Saturation limits
    localparam signed [DATA_BITS-1:0] MAX_VAL =  {1'b0, {(DATA_BITS-1){1'b1}}};
    localparam signed [DATA_BITS-1:0] MIN_VAL =  {1'b1, {(DATA_BITS-1){1'b0}}};

    wire signed [NORM_BITS-1:0] norm_full [0:NUM_FEATURES-1];
    wire signed [NORM_BITS-1:0] norm_round [0:NUM_FEATURES-1];
    wire signed [DATA_BITS:0]   norm_shifted [0:NUM_FEATURES-1]; // after >> 15

    generate
        for (k = 0; k < NUM_FEATURES; k = k + 1) begin : norm_mult
            // Sign-extend diff, zero-extend inv_sqrt for multiplication
            assign norm_full[k]    = $signed({{(INV_SQRT_BITS){diff[k][DATA_BITS]}}, diff[k]})
                                   * $signed({1'b0, inv_sqrt_s1});  // treat inv_sqrt as positive
            
            // Rounding: add 0.5 in Q(DATA_BITS+2).15 before shifting
            assign norm_round[k] = norm_full[k] + (1<<INV_SQRT_FRAC_BITS-1); // add 0.5 in Q format
            assign norm_shifted[k] = norm_round[k] >> INV_SQRT_FRAC_BITS; 
        end
    endgenerate

    integer dbg;

// always @(posedge clk) begin
//     if(valid_s2) begin
//         for(dbg=0; dbg<NUM_FEATURES; dbg=dbg+1) begin
//             $display("Cycle %0t: diff[%0d]=%0d inv_sqrt=%0d norm_full=%0d norm_round=%0d norm_shifted=%0d",
//                      $time,
//                      dbg,
//                      diff[dbg],
//                      inv_sqrt_s1,
//                      norm_full[dbg],
//                      norm_round[dbg],
//                      norm_shifted[dbg]);
//         end
//     end
// end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_s2 <= 0;
            for (i = 0; i < NUM_FEATURES; i = i + 1) begin
                norm[i]     <= 0;
                gamma_s2[i] <= 0;
                beta_s2[i]  <= 0;
            end
        end else begin
            valid_s2 <= valid_s1;
            for (i = 0; i < NUM_FEATURES; i = i + 1) begin
                // Saturate to DATA_BITS range
                if (norm_shifted[i] > $signed({{1{1'b0}}, MAX_VAL}))
                    norm[i] <= MAX_VAL;
                else if (norm_shifted[i] < $signed({{1{1'b1}}, MIN_VAL}))
                    norm[i] <= MIN_VAL;
                else
                    norm[i] <= norm_shifted[i][DATA_BITS-1:0];

                gamma_s2[i] <= gamma[i];
                beta_s2[i]  <= beta[i];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage 3: Scale and shift → out[i] = norm[i] * gamma[i] + beta[i]
    // norm is DATA_BITS signed
    // gamma is SCALE_BITS signed Q1.FRAC_BITS
    // product is DATA_BITS+SCALE_BITS, shift right FRAC_BITS, add beta
    // -------------------------------------------------------------------------
    localparam SCALED_BITS = DATA_BITS + SCALE_BITS;

    wire signed [SCALED_BITS-1:0]  scaled      [0:NUM_FEATURES-1];
    wire signed [DATA_BITS:0]      scaled_shift [0:NUM_FEATURES-1];
    wire signed [DATA_BITS+1:0]    biased       [0:NUM_FEATURES-1];

    wire signed [SCALED_BITS:0] scaled_plus_beta [0:NUM_FEATURES-1];

    generate
    for (k = 0; k < NUM_FEATURES; k = k + 1) begin : scale_shift
        // Step 1: multiply norm * gamma  →  Q(integer).(DATA_FRAC_BITS + FRAC_BITS)
        assign scaled[k] = $signed(norm[k]) * $signed(gamma_s2[k]);

        // Step 2: shift right by FRAC_BITS to remove gamma's fractional bits
        //         result is DATA_BITS+1 wide, same Q format as norm (Q13.DATA_FRAC_BITS)
        assign scaled_shift[k] = scaled[k][SCALED_BITS-1:FRAC_BITS];  // arithmetic >> FRAC_BITS

        // Step 3: align beta to the same domain as scaled_shift
        //         beta is Q1.FRAC_BITS, scaled_shift is Q13.DATA_FRAC_BITS
        //         beta must be left-shifted by (DATA_FRAC_BITS - FRAC_BITS) to align
        assign biased[k] = $signed({{1{scaled_shift[k][DATA_BITS]}}, scaled_shift[k]})
                 + $signed($signed({{(DATA_BITS+2-SCALE_BITS+DATA_FRAC_BITS-FRAC_BITS){beta_s2[k][SCALE_BITS-1]}},
                                    beta_s2[k]}) <<< (DATA_FRAC_BITS - FRAC_BITS));
    end
endgenerate


//        integer dbg;

// always @(posedge clk) begin
//     if(valid_s2) begin
//         for(dbg=0; dbg<NUM_FEATURES; dbg=dbg+1) begin
//             $display("Cycle %0t: scaled[%0d]=%0d  scaled_shift=%0d biased=%0d",
//                      $time,
//                      dbg,
//                      scaled[dbg],
//                      scaled_shift[dbg],

//                      biased[dbg]);
//         end
//     end
// end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_out <= 0;
            data_out  <= 0;
        end else begin
            valid_out <= valid_s2;
            for (i = 0; i < NUM_FEATURES; i = i + 1) begin
                // Saturate output back to DATA_BITS
                if (biased[i] > $signed({{2{1'b0}}, MAX_VAL}))
                    data_out[i*DATA_BITS +: DATA_BITS] <= MAX_VAL;
                else if (biased[i] < $signed({{2{1'b1}}, MIN_VAL}))
                    data_out[i*DATA_BITS +: DATA_BITS] <= MIN_VAL;
                else
                    data_out[i*DATA_BITS +: DATA_BITS] <= biased[i][DATA_BITS-1:0];
            end
        end
    end

endmodule