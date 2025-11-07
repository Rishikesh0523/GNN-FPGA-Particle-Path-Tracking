`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// layer_norm_mean.v
// Computes mean of NUM_FEATURES signed fixed-point values.
// Uses a pipelined adder tree (log2 stages).
//
// Latency: TREE_STAGES + 1 cycles after valid input
//   For NUM_FEATURES=32: 5 + 1 = 6 cycles
//
// Precision:
//   Input:  DATA_BITS wide (signed)
//   Sum:    DATA_BITS + log2(NUM_FEATURES) wide (to avoid overflow)
//   Mean:   DATA_BITS wide (truncated after divide-by-shift)
//------------------------------------------------------------------------------
module layer_norm_mean #(
    parameter NUM_FEATURES = 32,          // Must be power of 2
    parameter DATA_BITS    = 8,           // Bit width of each input
    // Derived
    parameter SUM_BITS     = DATA_BITS + 5 // log2(32)=5, enough for 32x8-bit sum
)(
    input  clk,
    input  rstn,
    input  valid_in,                                        // pulse: data_in is valid
    input  signed [NUM_FEATURES*DATA_BITS-1:0] data_in,    // flattened input features
    output reg valid_out,                                   // pulse: mean_out is valid
    output reg signed [DATA_BITS-1:0] mean_out             // computed mean
);

    // -------------------------------------------------------------------------
    // Unpack flat input into array
    // -------------------------------------------------------------------------
    wire signed [DATA_BITS-1:0] x [0:NUM_FEATURES-1];
    genvar k;
    generate
        for (k = 0; k < NUM_FEATURES; k = k + 1) begin : unpack
            assign x[k] = data_in[k*DATA_BITS +: DATA_BITS];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Adder tree - 5 stages for 32 inputs
    // Stage 0: 32 inputs  -> 16 sums (DATA_BITS+1 wide)
    // Stage 1: 16 sums    ->  8 sums (DATA_BITS+2 wide)
    // Stage 2:  8 sums    ->  4 sums (DATA_BITS+3 wide)
    // Stage 3:  4 sums    ->  2 sums (DATA_BITS+4 wide)
    // Stage 4:  2 sums    ->  1 sum  (DATA_BITS+5 wide)
    // -------------------------------------------------------------------------
    reg signed [DATA_BITS:0]   stage0 [0:15];  // 9-bit
    reg signed [DATA_BITS+1:0] stage1 [0:7];   // 10-bit
    reg signed [DATA_BITS+2:0] stage2 [0:3];   // 11-bit
    reg signed [DATA_BITS+3:0] stage3 [0:1];   // 12-bit
    reg signed [DATA_BITS+4:0] stage4;          // 13-bit

    // Valid pipeline delay line (5 stages for tree + 1 for mean output)
    reg [5:0] valid_pipe;

    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_pipe <= 6'b0;
            valid_out  <= 1'b0;
            mean_out   <= {DATA_BITS{1'b0}};
            stage4     <= {(DATA_BITS+5){1'b0}};
            for (i = 0; i < 16; i = i + 1) stage0[i] <= 0;
            for (i = 0; i < 8;  i = i + 1) stage1[i] <= 0;
            for (i = 0; i < 4;  i = i + 1) stage2[i] <= 0;
            for (i = 0; i < 2;  i = i + 1) stage3[i] <= 0;
        end else begin
            // Shift valid pipeline
            valid_pipe <= {valid_pipe[4:0], valid_in};

            // Stage 0: 32 -> 16
            for (i = 0; i < 16; i = i + 1)
                stage0[i] <= {{1{x[2*i][DATA_BITS-1]}},   x[2*i]}
                           + {{1{x[2*i+1][DATA_BITS-1]}}, x[2*i+1]};

            // Stage 1: 16 -> 8
            for (i = 0; i < 8; i = i + 1)
                stage1[i] <= {{1{stage0[2*i][DATA_BITS]}},   stage0[2*i]}
                           + {{1{stage0[2*i+1][DATA_BITS]}}, stage0[2*i+1]};

            // Stage 2: 8 -> 4
            for (i = 0; i < 4; i = i + 1)
                stage2[i] <= {{1{stage1[2*i][DATA_BITS+1]}},   stage1[2*i]}
                           + {{1{stage1[2*i+1][DATA_BITS+1]}}, stage1[2*i+1]};

            // Stage 3: 4 -> 2
            for (i = 0; i < 2; i = i + 1)
                stage3[i] <= {{1{stage2[2*i][DATA_BITS+2]}},   stage2[2*i]}
                           + {{1{stage2[2*i+1][DATA_BITS+2]}}, stage2[2*i+1]};

            // Stage 4: 2 -> 1
            stage4 <= {{1{stage3[0][DATA_BITS+3]}}, stage3[0]}
                    + {{1{stage3[1][DATA_BITS+3]}}, stage3[1]};

            // Mean = sum >> log2(NUM_FEATURES) = sum >> 5
            // Arithmetic right shift preserves sign
            valid_out <= valid_pipe[4];
            mean_out  <= stage4[DATA_BITS+4 -: DATA_BITS]; // upper DATA_BITS of sum = divide by 32
        end
    end

endmodule