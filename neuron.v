`timescale 1ns / 1ps
//==============================================================================
// neuron — N=4 parallel multiply-accumulate, drop-in replacement
//
// Counter now runs 1..NEURON_WIDTH/4 (set END_COUNTER=NUM_FEATURES/4 in layer).
// Each cycle processes 4 weight×data pairs and accumulates their sum.
// Timing matches original: multiplier is registered (1cy), adder starts at cy 2.
//
// Savings vs original:
//   L1 edge (192 features): 192 → 48 counter cycles
//   L1 node (128 features): 128 → 32 counter cycles
//   L2/L3   (32 features):   32 →  8 counter cycles
//==============================================================================
module neuron
#(
    parameter NEURON_WIDTH = 8,
    parameter DATA_BITS    = 16,
    parameter WEIGHT_BITS  = 32,
    parameter BIAS_BITS    = 16,
    parameter WeightFile   = "edge_encoder_w_1_0.mif",
    parameter BiasFile     = "edge_encoder_b_1_0.mif",
    parameter DEBUG         = 0
)
(
    input  clk,
    input  rstn,
    input  activation_function,

    // data_in_flat and weights are indexed 0..NEURON_WIDTH-1
    input  signed [NEURON_WIDTH*DATA_BITS-1:0] data_in_flat,

    // counter now counts 1..NEURON_WIDTH/4
    // (layer module sets END_COUNTER = NUM_FEATURES/4)
    input  [31:0] counter,

    output signed [DATA_BITS+WEIGHT_BITS+8-1:0] data_out
);

    localparam ACCUM_BITS = DATA_BITS + WEIGHT_BITS + 8;
    localparam N          = 4;   // parallel MACs

    /* Weights and bias */
    reg signed [WEIGHT_BITS-1:0] weights [0:NEURON_WIDTH-1];
    reg signed [BIAS_BITS-1:0]   bias_mem [0:0];
    wire signed [BIAS_BITS-1:0]  bias;
    assign bias = bias_mem[0];

    initial begin
        $readmemb(WeightFile, weights);
        $readmemb(BiasFile,   bias_mem);
    end

    // ── 4 parallel multiply lanes ─────────────────────────────────────────
    // At counter=c, process inputs [(c-1)*4 .. (c-1)*4+3] (0-indexed)
    // Uses counter-1 so index 0 is processed at counter=1 (matches original)

    wire signed [DATA_BITS-1:0]        x [0:N-1];
    wire signed [WEIGHT_BITS-1:0]      w [0:N-1];
    reg  signed [DATA_BITS+WEIGHT_BITS-1:0] prod [0:N-1];  // registered

    genvar k;
    generate
    for (k = 0; k < N; k = k + 1) begin : lane
        wire [31:0] idx = (counter >= 1) ? (counter-1)*N + k : 0;
        assign w[k] = (counter >= 1 && idx < NEURON_WIDTH) ? weights[idx] : 0;
        assign x[k] = (counter >= 1 && idx < NEURON_WIDTH) ? 
                      data_in_flat[idx*DATA_BITS +: DATA_BITS] : 0;

        always @(posedge clk or negedge rstn) begin
            if (!rstn) prod[k] <= 0;
            else       prod[k] <= w[k] * x[k];
            
            if (DEBUG && counter >= 1)
                $display("[%0t] Lane %0d: idx=%0d, x=%d, w=%d, prod=%d", $time, k, idx, x[k], w[k], prod[k]);
        end
    end
endgenerate

    // ── Adder tree: sum 4 registered products ─────────────────────────────
    // 2-level tree: (prod0+prod1) + (prod2+prod3)
    localparam SUM_BITS = DATA_BITS + WEIGHT_BITS + 2;  // 2 extra bits for 4-way sum

    wire signed [DATA_BITS+WEIGHT_BITS:0] s01, s23;
    assign s01 = {{1{prod[0][DATA_BITS+WEIGHT_BITS-1]}}, prod[0]}
               + {{1{prod[1][DATA_BITS+WEIGHT_BITS-1]}}, prod[1]};
    assign s23 = {{1{prod[2][DATA_BITS+WEIGHT_BITS-1]}}, prod[2]}
               + {{1{prod[3][DATA_BITS+WEIGHT_BITS-1]}}, prod[3]};

    wire signed [SUM_BITS-1:0] partial;
    assign partial = {{1{s01[DATA_BITS+WEIGHT_BITS]}}, s01}
                   + {{1{s23[DATA_BITS+WEIGHT_BITS]}}, s23};

    // ── Accumulator ───────────────────────────────────────────────────────
    // Timing: partial is ready 1 cycle after counter (multiplier latency)
    // So partial at cycle c+1 contains products for counter=c
    // Accumulate from counter=2 (partial contains products from counter=1)
    // This matches original adder.v behaviour exactly.

    reg signed [ACCUM_BITS-1:0] accumulator;
    reg signed [ACCUM_BITS-1:0] data_out_r;

    wire signed [ACCUM_BITS-1:0] partial_ext;
    assign partial_ext = {{(ACCUM_BITS-SUM_BITS){partial[SUM_BITS-1]}}, partial};

    
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        accumulator <= 0;
        data_out_r  <= 0;
    end
    else if (counter == 1) begin
        accumulator <= 0;
        data_out_r  <= 0;
        if (DEBUG)
        $display("[%0t] Counter 1: reset accumulator", $time);
    end
    else if (counter == 2) begin
        accumulator <= accumulator+partial_ext;
        data_out_r  <= accumulator+partial_ext;
        if (DEBUG)
        $display("[%0t] Counter 2: first accumulation %d", $time, partial_ext);
    end
    else if (counter >= 3) begin
        accumulator <= accumulator + partial_ext;
        data_out_r  <= accumulator;
        if (DEBUG)
        $display("[%0t] Counter %d: accumulator updated %d", $time, counter, accumulator + partial_ext);
    end
end

    assign data_out = data_out_r;

endmodule