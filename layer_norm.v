`timescale 1ns / 1ps
//==============================================================================
// layer_norm.v  —  Layer Normalization Top-Level (Moore FSM)
//
// Formula: y_i = ((x_i - mean) / sqrt(var + epsilon)) * gamma_i + beta_i
// Optional ReLU + requantize Q14.10 → Q4.4 at output
//
// States:
//   S_IDLE        : waiting for valid_in pulse
//   S_CAPTURE     : latch data_in/gamma/beta/act_en, start mean submodule
//   S_WAIT_MEAN   : wait for mean submodule valid_out
//   S_START_VAR   : register mean result, start variance submodule
//   S_WAIT_VAR    : wait for variance submodule valid_out
//   S_START_SQRT  : register variance result, start inv_sqrt submodule
//   S_WAIT_SQRT   : wait for inv_sqrt submodule valid_out
//   S_START_NORM  : register inv_sqrt result, start normalize submodule
//   S_WAIT_NORM   : wait for normalize submodule valid_out
//   S_START_RELU  : register norm result, start relu submodule
//   S_WAIT_RELU   : wait for relu submodule valid_out (1 cycle)
//   S_OUTPUT      : register final output, assert valid_out for 1 cycle
//
// Submodule latencies:
//   mean      : 6 cycles
//   variance  : 7 cycles
//   inv_sqrt  : 4 cycles
//   normalize : 3 cycles
//   relu      : 1 cycle
//==============================================================================
module layer_norm #(
    parameter NUM_FEATURES       = 32,
    parameter DATA_BITS          = 24,      // Q14.10
    parameter DATA_FRAC_BITS     = 10,
    parameter SCALE_BITS         = 8,
    parameter FRAC_BITS          = 6,
    parameter INV_SQRT_BITS      = 16,
    parameter INV_SQRT_FRAC_BITS = 11,      // Q5.11
    parameter VAR_BITS           = 45,
    parameter LUT_BITS           = 5,
    parameter LUT_SIZE           = 20,
    parameter EPSILON            = 1,
    parameter OUT_BITS           = 8,       // Q4.4 output
    parameter OUT_FRAC_BITS      = 4
)(
    input  clk,
    input  rstn,

    // Control
    input  valid_in,
    input  act_en,                                              // 1 = apply ReLU

    // Data inputs
    input  signed [NUM_FEATURES*DATA_BITS-1:0]   data_in,
    input  signed [NUM_FEATURES*SCALE_BITS-1:0]  gamma,
    input  signed [NUM_FEATURES*SCALE_BITS-1:0]  beta,

    // Outputs
    output reg valid_out,
    output reg busy,
    output reg signed [NUM_FEATURES*OUT_BITS-1:0] data_out     // Q4.4
);

    //--------------------------------------------------------------------------
    // State encoding
    //--------------------------------------------------------------------------
    localparam [3:0]
        S_IDLE       = 4'd0,
        S_CAPTURE    = 4'd1,
        S_WAIT_MEAN  = 4'd2,
        S_START_VAR  = 4'd3,
        S_WAIT_VAR   = 4'd4,
        S_START_SQRT = 4'd5,
        S_WAIT_SQRT  = 4'd6,
        S_START_NORM = 4'd7,
        S_WAIT_NORM  = 4'd8,
        S_START_RELU = 4'd9,
        S_WAIT_RELU  = 4'd10,
        S_OUTPUT     = 4'd11;

    reg [3:0] state, next_state;

    //--------------------------------------------------------------------------
    // Internal data registers
    //--------------------------------------------------------------------------
    reg signed [NUM_FEATURES*DATA_BITS-1:0]  r_data;
    reg signed [NUM_FEATURES*SCALE_BITS-1:0] r_gamma;
    reg signed [NUM_FEATURES*SCALE_BITS-1:0] r_beta;
    reg signed [DATA_BITS-1:0]               r_mean;
    reg        [VAR_BITS-1:0]                r_variance;
    reg        [INV_SQRT_BITS-1:0]           r_inv_sqrt;
    reg signed [NUM_FEATURES*DATA_BITS-1:0]  r_norm_result;
    reg                                      r_act_en;

    //--------------------------------------------------------------------------
    // Submodule control pulses
    //--------------------------------------------------------------------------
    reg mean_start;
    reg var_start;
    reg sqrt_start;
    reg norm_start;
    reg relu_start;

    //--------------------------------------------------------------------------
    // Submodule result wires
    //--------------------------------------------------------------------------
    wire                                      mean_valid_out;
    wire signed [DATA_BITS-1:0]               mean_result;

    wire                                      var_valid_out;
    wire [VAR_BITS-1:0]                       var_result;

    wire                                      sqrt_valid_out;
    wire [INV_SQRT_BITS-1:0]                  sqrt_result;

    wire                                      norm_valid_out;
    wire signed [NUM_FEATURES*DATA_BITS-1:0]  norm_result;

    wire                                      relu_valid_out;
    wire signed [NUM_FEATURES*OUT_BITS-1:0]   relu_result;

    //--------------------------------------------------------------------------
    // State register
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    //--------------------------------------------------------------------------
    // Next-state logic (combinational)
    //--------------------------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:       if (valid_in)        next_state = S_CAPTURE;
            S_CAPTURE:                          next_state = S_WAIT_MEAN;
            S_WAIT_MEAN:  if (mean_valid_out)   next_state = S_START_VAR;
            S_START_VAR:                        next_state = S_WAIT_VAR;
            S_WAIT_VAR:   if (var_valid_out)    next_state = S_START_SQRT;
            S_START_SQRT:                       next_state = S_WAIT_SQRT;
            S_WAIT_SQRT:  if (sqrt_valid_out)   next_state = S_START_NORM;
            S_START_NORM:                       next_state = S_WAIT_NORM;
            S_WAIT_NORM:  if (norm_valid_out)   next_state = S_START_RELU;
            S_START_RELU:                       next_state = S_WAIT_RELU;
            S_WAIT_RELU:  if (relu_valid_out)   next_state = S_OUTPUT;
            S_OUTPUT:                           next_state = S_IDLE;
            default:                            next_state = S_IDLE;
        endcase
    end

    //--------------------------------------------------------------------------
    // Moore output + datapath registered logic
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_out     <= 1'b0;
            busy          <= 1'b0;
            data_out      <= {(NUM_FEATURES*OUT_BITS){1'b0}};
            mean_start    <= 1'b0;
            var_start     <= 1'b0;
            sqrt_start    <= 1'b0;
            norm_start    <= 1'b0;
            relu_start    <= 1'b0;
            r_data        <= {(NUM_FEATURES*DATA_BITS){1'b0}};
            r_gamma       <= {(NUM_FEATURES*SCALE_BITS){1'b0}};
            r_beta        <= {(NUM_FEATURES*SCALE_BITS){1'b0}};
            r_mean        <= {DATA_BITS{1'b0}};
            r_variance    <= {VAR_BITS{1'b0}};
            r_inv_sqrt    <= {INV_SQRT_BITS{1'b0}};
            r_norm_result <= {(NUM_FEATURES*DATA_BITS){1'b0}};
            r_act_en      <= 1'b0;
        end else begin
            // Default: clear all pulses every cycle
            mean_start <= 1'b0;
            var_start  <= 1'b0;
            sqrt_start <= 1'b0;
            norm_start <= 1'b0;
            relu_start <= 1'b0;
            valid_out  <= 1'b0;

            case (next_state)

                //--------------------------------------------------------------
                S_IDLE: begin
                    busy      <= 1'b0;
                    valid_out <= 1'b0;
                end

                //--------------------------------------------------------------
                // Latch all inputs, start mean
                //--------------------------------------------------------------
                S_CAPTURE: begin
                    busy       <= 1'b1;
                    r_data     <= data_in;
                    r_gamma    <= gamma;
                    r_beta     <= beta;
                    r_act_en   <= act_en;
                    mean_start <= 1'b1;
                end

                S_WAIT_MEAN: begin
                    busy <= 1'b1;
                end

                //--------------------------------------------------------------
                // Latch mean, start variance
                //--------------------------------------------------------------
                S_START_VAR: begin
                    busy      <= 1'b1;
                    r_mean    <= mean_result;
                    var_start <= 1'b1;
                    // $display("Cycle %0t: mean = %0d", $time, mean_result);
                end

                S_WAIT_VAR: begin
                    busy <= 1'b1;
                end

                //--------------------------------------------------------------
                // Latch variance, start inv_sqrt
                //--------------------------------------------------------------
                S_START_SQRT: begin
                    busy       <= 1'b1;
                    r_variance <= var_result;
                    sqrt_start <= 1'b1;
                    // $display("Cycle %0t: variance = %0d", $time, var_result);
                end

                S_WAIT_SQRT: begin
                    busy <= 1'b1;
                end

                //--------------------------------------------------------------
                // Latch inv_sqrt, start normalize
                //--------------------------------------------------------------
                S_START_NORM: begin
                    busy       <= 1'b1;
                    r_inv_sqrt <= sqrt_result;
                    norm_start <= 1'b1;
                    // $display("Cycle %0t: inv_sqrt = %0d", $time, sqrt_result);
                end

                S_WAIT_NORM: begin
                    busy <= 1'b1;
                end

                //--------------------------------------------------------------
                // Latch normalize result, start relu
                //--------------------------------------------------------------
                S_START_RELU: begin
                    busy          <= 1'b1;
                    r_norm_result <= norm_result;
                    relu_start    <= 1'b1;
                    // $display("Cycle %0t: norm_result latched, starting relu", $time);
                end

                S_WAIT_RELU: begin
                    busy       <= 1'b1;
                    relu_start <= 1'b0;
                end

                //--------------------------------------------------------------
                // Latch relu result, assert valid_out
                //--------------------------------------------------------------
                S_OUTPUT: begin
                    busy      <= 1'b0;
                    valid_out <= 1'b1;
                    data_out  <= relu_result;
                    // $display("Cycle %0t: valid_out asserted, data_out = %h",
                    //          $time, relu_result);
                end

                default: begin
                    busy      <= 1'b0;
                    valid_out <= 1'b0;
                end

            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Submodule: Mean
    //--------------------------------------------------------------------------
    layer_norm_mean #(
        .NUM_FEATURES(NUM_FEATURES),
        .DATA_BITS   (DATA_BITS)
    ) u_mean (
        .clk      (clk),
        .rstn     (rstn),
        .valid_in (mean_start),
        .data_in  (r_data),
        .valid_out(mean_valid_out),
        .mean_out (mean_result)
    );

    //--------------------------------------------------------------------------
    // Submodule: Variance
    //--------------------------------------------------------------------------
    layer_norm_variance #(
        .NUM_FEATURES  (NUM_FEATURES),
        .DATA_BITS     (DATA_BITS),
        .DATA_FRAC_BITS(DATA_FRAC_BITS)
    ) u_variance (
        .clk         (clk),
        .rstn        (rstn),
        .valid_in    (var_start),
        .data_in     (r_data),
        .mean_in     (r_mean),
        .valid_out   (var_valid_out),
        .variance_out(var_result)
    );

    //--------------------------------------------------------------------------
    // Submodule: Inverse square root
    //--------------------------------------------------------------------------
    layer_norm_inv_sqrt #(
        .VAR_BITS     (VAR_BITS),
        .VAR_FRAC_BITS(15),
        .LUT_BITS     (LUT_BITS),
        .LUT_SIZE     (LUT_SIZE),
        .OUT_BITS     (INV_SQRT_BITS),
        .OUT_FRAC_BITS(INV_SQRT_FRAC_BITS)
    ) u_inv_sqrt (
        .clk         (clk),
        .rstn        (rstn),
        .valid_in    (sqrt_start),
        .variance_in (r_variance),
        .valid_out   (sqrt_valid_out),
        .inv_sqrt_out(sqrt_result)
    );

    //--------------------------------------------------------------------------
    // Submodule: Normalize + scale + shift
    //--------------------------------------------------------------------------
    layer_norm_normalize #(
        .NUM_FEATURES      (NUM_FEATURES),
        .DATA_BITS         (DATA_BITS),
        .DATA_FRAC_BITS    (DATA_FRAC_BITS),
        .INV_SQRT_BITS     (INV_SQRT_BITS),
        .INV_SQRT_FRAC_BITS(INV_SQRT_FRAC_BITS),
        .SCALE_BITS        (SCALE_BITS),
        .FRAC_BITS         (FRAC_BITS)
    ) u_normalize (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (norm_start),
        .data_in    (r_data),
        .mean_in    (r_mean),
        .inv_sqrt_in(r_inv_sqrt),
        .gamma_flat (r_gamma),
        .beta_flat  (r_beta),
        .valid_out  (norm_valid_out),
        .data_out   (norm_result)
    );

    //--------------------------------------------------------------------------
    // Submodule: ReLU + requantize Q14.10 → Q4.4
    //--------------------------------------------------------------------------
    layer_norm_relu #(
        .NUM_FEATURES  (NUM_FEATURES),
        .DATA_BITS     (DATA_BITS),
        .DATA_FRAC_BITS(DATA_FRAC_BITS),
        .OUT_BITS      (OUT_BITS),
        .OUT_FRAC_BITS (OUT_FRAC_BITS)
    ) u_relu (
        .clk      (clk),
        .rstn     (rstn),
        .valid_in (relu_start),
        .act_en   (r_act_en),           // latched at capture — stable for entire pipeline
        .data_in  (r_norm_result),      // registered Q14.10 from S_START_RELU
        .valid_out(relu_valid_out),
        .data_out (relu_result)
    );

endmodule