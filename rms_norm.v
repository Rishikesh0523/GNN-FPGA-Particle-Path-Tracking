`timescale 1ns / 1ps
//==============================================================================
// rms_norm.v  —  RMS Normalization Top-Level (Moore FSM)
//
// Formula: y_i = (x_i / sqrt(mean(x^2) + epsilon)) * gamma_i
// Optional ReLU + requantize Q14.10 → Q4.4 at output.
//
// States:
//   S_IDLE       : waiting for valid_in pulse
//   S_CAPTURE    : latch data_in/gamma/act_en, start rms submodule
//   S_WAIT_RMS   : wait for rms submodule valid_out  (8 cycles)
//   S_START_SQRT : register rms result, start inv_sqrt submodule
//   S_WAIT_SQRT  : wait for inv_sqrt submodule valid_out (4 cycles)
//   S_START_NORM : register inv_sqrt result, start normalize submodule
//   S_WAIT_NORM  : wait for normalize submodule valid_out (2 cycles)
//   S_START_RELU : register norm result, start relu submodule
//   S_WAIT_RELU  : wait for relu submodule valid_out (1 cycle)
//   S_OUTPUT     : register final output, assert valid_out for 1 cycle
//
// Total latency: ~17 cycles (vs ~22 for layer_norm)
// Submodule latencies:
//   rms       : 8 cycles
//   inv_sqrt  : 4 cycles
//   normalize : 2 cycles
//   relu      : 1 cycle
//==============================================================================
module rms_norm #(
    parameter NUM_FEATURES       = 32,
    parameter DATA_BITS          = 24,
    parameter DATA_FRAC_BITS     = 10,
    parameter SCALE_BITS         = 8,
    parameter FRAC_BITS          = 6,
    parameter INV_SQRT_BITS      = 16,
    parameter INV_SQRT_FRAC_BITS = 11,
    parameter VAR_BITS           = 45,
    parameter LUT_BITS           = 5,
    parameter LUT_SIZE           = 20,
    parameter EPSILON            = 1,
    parameter OUT_BITS           = 8,
    parameter OUT_FRAC_BITS      = 4
)(
    input  clk,
    input  rstn,
    input  valid_in,
    input  act_en,

    input  signed [NUM_FEATURES*DATA_BITS-1:0]  data_in,
    input  signed [NUM_FEATURES*SCALE_BITS-1:0] gamma,
    // Note: no beta port — RMSNorm has no additive offset

    output reg valid_out,
    output reg busy,
    output reg signed [NUM_FEATURES*OUT_BITS-1:0] data_out
);

    localparam [3:0]
        S_IDLE       = 4'd0,
        S_CAPTURE    = 4'd1,
        S_WAIT_RMS   = 4'd2,
        S_START_SQRT = 4'd3,
        S_WAIT_SQRT  = 4'd4,
        S_START_NORM = 4'd5,
        S_WAIT_NORM  = 4'd6,
        S_START_RELU = 4'd7,
        S_WAIT_RELU  = 4'd8,
        S_OUTPUT     = 4'd9;

    reg [3:0] state, next_state;

    reg signed [NUM_FEATURES*DATA_BITS-1:0]  r_data;
    reg signed [NUM_FEATURES*SCALE_BITS-1:0] r_gamma;
    reg        [VAR_BITS-1:0]                r_rms;
    reg        [INV_SQRT_BITS-1:0]           r_inv_sqrt;
    reg signed [NUM_FEATURES*DATA_BITS-1:0]  r_norm_result;
    reg                                      r_act_en;

    reg rms_start, sqrt_start, norm_start, relu_start;

    wire                                     rms_valid_out;
    wire [VAR_BITS-1:0]                      rms_result;

    wire                                     sqrt_valid_out;
    wire [INV_SQRT_BITS-1:0]                 sqrt_result;

    wire                                     norm_valid_out;
    wire signed [NUM_FEATURES*DATA_BITS-1:0] norm_result;

    wire                                     relu_valid_out;
    wire signed [NUM_FEATURES*OUT_BITS-1:0]  relu_result;

    // State register
    always @(posedge clk or negedge rstn) begin
        if (!rstn) state <= S_IDLE;
        else        state <= next_state;
    end

    // Next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:       if (valid_in)       next_state = S_CAPTURE;
            S_CAPTURE:                         next_state = S_WAIT_RMS;
            S_WAIT_RMS:   if (rms_valid_out)  next_state = S_START_SQRT;
            S_START_SQRT:                      next_state = S_WAIT_SQRT;
            S_WAIT_SQRT:  if (sqrt_valid_out) next_state = S_START_NORM;
            S_START_NORM:                      next_state = S_WAIT_NORM;
            S_WAIT_NORM:  if (norm_valid_out) next_state = S_START_RELU;
            S_START_RELU:                      next_state = S_WAIT_RELU;
            S_WAIT_RELU:  if (relu_valid_out) next_state = S_OUTPUT;
            S_OUTPUT:                          next_state = S_IDLE;
            default:                           next_state = S_IDLE;
        endcase
    end

    // Output + datapath
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_out     <= 0; busy      <= 0;
            data_out      <= 0;
            rms_start     <= 0; sqrt_start <= 0;
            norm_start    <= 0; relu_start  <= 0;
            r_data        <= 0; r_gamma    <= 0;
            r_rms         <= 0; r_inv_sqrt <= 0;
            r_norm_result <= 0; r_act_en   <= 0;
        end else begin
            rms_start  <= 0; sqrt_start <= 0;
            norm_start <= 0; relu_start  <= 0;
            valid_out  <= 0;

            case (next_state)
                S_IDLE: begin
                    busy <= 0;
                end

                S_CAPTURE: begin
                    busy      <= 1;
                    r_data    <= data_in;
                    r_gamma   <= gamma;
                    r_act_en  <= act_en;
                    rms_start <= 1;
                end

                S_WAIT_RMS: busy <= 1;

                S_START_SQRT: begin
                    busy       <= 1;
                    r_rms      <= rms_result;
                    sqrt_start <= 1;
                end

                S_WAIT_SQRT: busy <= 1;

                S_START_NORM: begin
                    busy       <= 1;
                    r_inv_sqrt <= sqrt_result;
                    norm_start <= 1;
                end

                S_WAIT_NORM: busy <= 1;

                S_START_RELU: begin
                    busy          <= 1;
                    r_norm_result <= norm_result;
                    relu_start    <= 1;
                end

                S_WAIT_RELU: busy <= 1;

                S_OUTPUT: begin
                    busy      <= 0;
                    valid_out <= 1;
                    data_out  <= relu_result;
                end

                default: begin busy <= 0; valid_out <= 0; end
            endcase
        end
//         if (rms_valid_out) begin
//     $display("[DEBUG][%0t] RMS RAW = %d", $time, rms_result);
// end
//         if (sqrt_valid_out) begin
//     $display("[DEBUG][%0t] INV SQRT = %d", $time, sqrt_result);
// end

    end

    //--------------------------------------------------------------------------
    // Submodule: RMS  (replaces mean + variance)
    //--------------------------------------------------------------------------
    rms_norm_rms #(
        .NUM_FEATURES  (NUM_FEATURES),
        .DATA_BITS     (DATA_BITS),
        .DATA_FRAC_BITS(DATA_FRAC_BITS)
    ) u_rms (
        .clk      (clk),
        .rstn     (rstn),
        .valid_in (rms_start),
        .data_in  (r_data),
        .valid_out(rms_valid_out),
        .rms_out  (rms_result)
    );

    //--------------------------------------------------------------------------
    // Submodule: Inverse square root  (reused unchanged)
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
        .variance_in (r_rms),
        .valid_out   (sqrt_valid_out),
        .inv_sqrt_out(sqrt_result)
    );

    //--------------------------------------------------------------------------
    // Submodule: Normalize + scale  (no mean subtraction, no beta)
    //--------------------------------------------------------------------------
    rms_norm_normalize #(
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
        .inv_sqrt_in(r_inv_sqrt),
        .gamma_flat (r_gamma),
        .valid_out  (norm_valid_out),
        .data_out   (norm_result)
    );

    //--------------------------------------------------------------------------
    // Submodule: ReLU + requantize  (reused unchanged)
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
        .act_en   (r_act_en),
        .data_in  (r_norm_result),
        .valid_out(relu_valid_out),
        .data_out (relu_result)
    );

endmodule