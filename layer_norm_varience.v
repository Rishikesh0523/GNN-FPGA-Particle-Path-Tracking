// layer_norm_varience.v
// Streaming variance accumulator. Accumulator widened by
// EXTRA_BITS to avoid saturation across long feature dims.
`timescale 1ns / 1ps
module layer_norm_variance #(
    parameter NUM_FEATURES   = 32,
    parameter DATA_BITS      = 24,
    parameter DATA_FRAC_BITS = 10
)(
    input  clk,
    input  rstn,
    input  valid_in,
    input  signed [NUM_FEATURES*DATA_BITS-1:0] data_in,
    input  signed [DATA_BITS-1:0]              mean_in,
    output reg valid_out,
    output reg [VAR_BITS-1:0] variance_out
);

    // Derived widths
    localparam DIFF_BITS         = DATA_BITS + 1;            // 25
    localparam SQ_BITS           = 2 * DIFF_BITS;            // 50
    localparam SUM_BITS          = SQ_BITS + 5;              // 55  (for 32 features)
    localparam VAR_FRAC_BITS     = 2*DATA_FRAC_BITS - 5;     // 15  (frac bits after >>5)
    localparam VAR_INT_BITS      = 2*(DATA_BITS - DATA_FRAC_BITS) + 1 + 1; // 2*14+2 = 30
    localparam VAR_BITS          = VAR_INT_BITS + VAR_FRAC_BITS; // 30 + 15 = 45
    // Use 45 bits: safe integer headroom + full fractional precision for LUT

    wire signed [DATA_BITS-1:0] x [0:NUM_FEATURES-1];
    genvar k;
    generate
        for (k = 0; k < NUM_FEATURES; k = k + 1) begin : unpack
            assign x[k] = data_in[k*DATA_BITS +: DATA_BITS];
        end
    endgenerate

    reg signed [DIFF_BITS-1:0] diff   [0:NUM_FEATURES-1];
    reg        [SQ_BITS-1:0]   sq     [0:NUM_FEATURES-1];
    reg valid_s0, valid_s1;

    // Adder tree: 5 levels for 32 inputs, each level adds 1 bit
    reg [SQ_BITS  :0] atree1 [0:15];   // SQ_BITS+1 = 51
    reg [SQ_BITS+1:0] atree2 [0:7];    // 52
    reg [SQ_BITS+2:0] atree3 [0:3];    // 53
    reg [SQ_BITS+3:0] atree4 [0:1];    // 54
    reg [SQ_BITS+4:0] atree5;          // 55  = SUM_BITS
    reg valid_a1, valid_a2, valid_a3, valid_a4, valid_a5;

    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_s0 <= 0; valid_s1 <= 0;
            valid_a1 <= 0; valid_a2 <= 0; valid_a3 <= 0;
            valid_a4 <= 0; valid_a5 <= 0;
            valid_out    <= 0;
            variance_out <= 0;
            atree5 <= 0;
            for (i = 0; i < NUM_FEATURES; i = i + 1) begin
                diff[i] <= 0;
                sq[i]   <= 0;
            end
            for (i = 0; i < 16; i = i + 1) atree1[i] <= 0;
            for (i = 0; i < 8;  i = i + 1) atree2[i] <= 0;
            for (i = 0; i < 4;  i = i + 1) atree3[i] <= 0;
            for (i = 0; i < 2;  i = i + 1) atree4[i] <= 0;
        end else begin

            // Stage 0: subtract mean
            valid_s0 <= valid_in;
            for (i = 0; i < NUM_FEATURES; i = i + 1)
                diff[i] <= {{1{x[i][DATA_BITS-1]}}, x[i]}
                         - {{1{mean_in[DATA_BITS-1]}}, mean_in};

            // Stage 1: square (always positive)
            valid_s1 <= valid_s0;
            for (i = 0; i < NUM_FEATURES; i = i + 1)
                sq[i] <= diff[i] * diff[i];

            // Adder tree: 32 → 1
            valid_a1 <= valid_s1;
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

            // Divide by 32 (>> 5): drop bottom 5 bits, keep upper VAR_BITS
            // atree5 is SUM_BITS=55 wide; >>5 gives 50 meaningful bits
            // VAR_BITS=45 so take bits [49:5] of atree5
            valid_out    <= valid_a5;
            variance_out <= atree5[SUM_BITS-1 : SUM_BITS-VAR_BITS];
        end
    end

endmodule