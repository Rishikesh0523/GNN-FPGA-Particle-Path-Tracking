`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// rms_norm_rms.v
// Computes RMS value: mean(x^2) = (1/N) * sum(x_i^2)
//
// Replaces layer_norm_mean + layer_norm_variance.
// No mean subtraction needed — RMSNorm centers around 0 by design.
//
// Latency: 8 cycles  (2 sq + 5 adder tree + 1 divide/output)
//   For NUM_FEATURES=32: log2(32)=5 adder tree stages
//
// Fixed-point:
//   Input:  DATA_BITS signed Q(DATA_BITS-DATA_FRAC_BITS).DATA_FRAC_BITS
//   x^2:    2*DATA_BITS unsigned (always positive)
//   sum:    2*DATA_BITS + log2(NUM_FEATURES) wide
//   mean:   VAR_BITS wide (same format as layer_norm variance output
//           so inv_sqrt LUT is reusable without modification)
//------------------------------------------------------------------------------
module rms_norm_rms #(
    parameter NUM_FEATURES   = 32,
    parameter DATA_BITS      = 24,
    parameter DATA_FRAC_BITS = 10
)(
    input  clk,
    input  rstn,
    input  valid_in,
    input  signed [NUM_FEATURES*DATA_BITS-1:0] data_in,
    output reg valid_out,
    output reg [VAR_BITS-1:0] rms_out      // same port name/width as variance_out
);
    // Mirror the exact width derivation from layer_norm_varience.v so the
    // inv_sqrt LUT thresholds remain valid.
    localparam SQ_BITS   = 2 * DATA_BITS;             // 48
    localparam SUM_BITS  = SQ_BITS + 5;               // 53  (log2(32)=5)
    localparam VAR_FRAC_BITS = 2*DATA_FRAC_BITS - 5;  // 15
    localparam VAR_INT_BITS  = 2*(DATA_BITS - DATA_FRAC_BITS) + 1 + 1; // 30
    localparam VAR_BITS  = VAR_INT_BITS + VAR_FRAC_BITS; // 45

    // Unpack
    wire signed [DATA_BITS-1:0] x [0:NUM_FEATURES-1];
    genvar k;
    generate
        for (k = 0; k < NUM_FEATURES; k = k + 1) begin : unpack
            assign x[k] = data_in[k*DATA_BITS +: DATA_BITS];
        end
    endgenerate

    // Stage 0: square each input (always non-negative)
    reg [SQ_BITS-1:0] sq [0:NUM_FEATURES-1];
    reg valid_s0;

    // Adder tree: 5 levels for 32 inputs
    reg [SQ_BITS  :0] atree1 [0:15];
    reg [SQ_BITS+1:0] atree2 [0:7];
    reg [SQ_BITS+2:0] atree3 [0:3];
    reg [SQ_BITS+3:0] atree4 [0:1];
    reg [SQ_BITS+4:0] atree5;
    reg valid_a1, valid_a2, valid_a3, valid_a4, valid_a5;

    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_s0 <= 0;
            valid_a1 <= 0; valid_a2 <= 0; valid_a3 <= 0;
            valid_a4 <= 0; valid_a5 <= 0;
            valid_out <= 0;
            rms_out   <= 0;
            atree5 <= 0;
            for (i = 0; i < NUM_FEATURES; i = i + 1) sq[i] <= 0;
            for (i = 0; i < 16; i = i + 1) atree1[i] <= 0;
            for (i = 0; i < 8;  i = i + 1) atree2[i] <= 0;
            for (i = 0; i < 4;  i = i + 1) atree3[i] <= 0;
            for (i = 0; i < 2;  i = i + 1) atree4[i] <= 0;
        end else begin
            // Stage 0: x^2  (signed * signed = unsigned result, always >= 0)
            valid_s0 <= valid_in;
            for (i = 0; i < NUM_FEATURES; i = i + 1)
                sq[i] <= x[i] * x[i];

            // Adder tree: 32 → 1
            valid_a1 <= valid_s0;
            for (i = 0; i < 16; i = i + 1)
                atree1[i] <= {1'b0, sq[2*i]} + {1'b0, sq[2*i+1]};

            valid_a2 <= valid_a1;
            for (i = 0; i < 8; i = i + 1)
                atree2[i] <= {1'b0, atree1[2*i]} + {1'b0, atree1[2*i+1]};

            valid_a3 <= valid_a2;
            for (i = 0; i < 4; i = i + 1)
                atree3[i] <= {1'b0, atree2[2*i]} + {1'b0, atree2[2*i+1]};

            valid_a4 <= valid_a3;
            for (i = 0; i < 2; i = i + 1)
                atree4[i] <= {1'b0, atree3[2*i]} + {1'b0, atree3[2*i+1]};

            valid_a5 <= valid_a4;
            atree5 <= {1'b0, atree4[0]} + {1'b0, atree4[1]};

            // Divide by 32 (>> 5): same slice as variance module
            // atree5 is SUM_BITS=53 wide; VAR_BITS=45 → take top 45 bits
            valid_out <= valid_a5;
            rms_out   <= (atree5 >> 5);
        end
        
    end

endmodule