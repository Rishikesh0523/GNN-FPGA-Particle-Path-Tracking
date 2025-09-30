`timescale 1ns / 1ps
module ReLu
#(
    parameter DATA_BITS   = 8,
    parameter WEIGHT_BITS = 8,
    parameter COUNTER_END = 6,  
    parameter BIAS_BITS   = 8,
    parameter ACCUM_EXTRA = 8,
    parameter WEIGHT_FRAC_BITS = 6,
    parameter DATA_FRAC_BITS = 4,
    parameter BIAS_FRAC_BITS = 4
)
(
    input  clk,
    input  rstn,
    input  activation_function,
    input  [31:0] counter,
    input  signed [DATA_BITS+WEIGHT_BITS+ACCUM_EXTRA-1:0] mult_sum_in,
    input  signed [BIAS_BITS-1:0] b,
    output reg signed [DATA_BITS-1:0] neuron_out
);
    localparam ACCUM_FRAC_BITS = WEIGHT_FRAC_BITS + DATA_FRAC_BITS;

    reg signed [DATA_BITS+WEIGHT_BITS+ACCUM_EXTRA-1:0] biased_sum;
    reg signed [DATA_BITS-1:0] neuron_out_next;
    
    localparam signed [DATA_BITS-1:0] OUT_MAX = {1'b0, {(DATA_BITS-1){1'b1}}}; // 0b0111_1111 = +127
    localparam signed [DATA_BITS-1:0] OUT_MIN = {1'b1, {(DATA_BITS-1){1'b0}}}; // 0b1000_0000 = -128

    localparam signed [DATA_BITS+WEIGHT_BITS+ACCUM_EXTRA-1:0] MAX_VAL = {{(WEIGHT_BITS+ACCUM_EXTRA){1'b0}}, OUT_MAX};

    localparam signed [DATA_BITS+WEIGHT_BITS+ACCUM_EXTRA-1:0] MIN_VAL = {{(WEIGHT_BITS+ACCUM_EXTRA){1'b1}}, OUT_MIN};
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            neuron_out <= {DATA_BITS{1'b0}};
            biased_sum <= {(DATA_BITS+WEIGHT_BITS+ACCUM_EXTRA){1'b0}};
        end
        // Activate when we reach the last feature counter value
        else if (counter == COUNTER_END) begin
            // Add bias
            biased_sum = mult_sum_in + {{(DATA_BITS+WEIGHT_BITS+ACCUM_EXTRA-BIAS_BITS){b[BIAS_BITS-1]}}, b};

            // $display("[%0t] ReLu: ACTIVATING at counter=%d (COUNTER_END), mult_sum_in=%d, bias=%d, biased_sum=%d", 
            //          $time, counter, $signed(mult_sum_in), $signed(b), $signed(biased_sum));

            if (activation_function) begin
                /* ReLU with saturation */
                if (biased_sum < 0) begin
                    neuron_out_next = {DATA_BITS{1'b0}};
                    // $display("[%0t] ReLu: ReLU clamp to 0, biased_sum=%d, neuron_out=%d", 
                    //          $time, $signed(biased_sum), $signed(neuron_out_next));
                end
                else if (biased_sum > MAX_VAL) begin
                    neuron_out_next = OUT_MAX;
                    // $display("[%0t] ReLu: Saturation, biased_sum=%d > MAX_VAL=%d, neuron_out=%d", 
                    //          $time, $signed(biased_sum), $signed(MAX_VAL), $signed(neuron_out_next));
                end
                else begin
                    neuron_out_next = biased_sum[DATA_BITS+WEIGHT_BITS-WEIGHT_FRAC_BITS-1 -:DATA_BITS];
                    // $display("[%0t] ReLu: Normal output, biased_sum=%d, neuron_out=%d", 
                    //          $time, $signed(biased_sum), $signed(neuron_out_next));
                end
                neuron_out <= neuron_out_next;
            end
            else begin
                /* Linear with saturation */
                if (biased_sum > MAX_VAL) begin
                    neuron_out_next = OUT_MAX;
                    // $display("[%0t] Linear: Positive saturation, biased_sum=%d, neuron_out=%d", 
                    //          $time, $signed(biased_sum), $signed(neuron_out_next));
                end
                else if (biased_sum < MIN_VAL) begin
                    neuron_out_next = OUT_MIN;
                    // $display("[%0t] Linear: Negative saturation, biased_sum=%d, neuron_out=%d", 
                    //          $time, $signed(biased_sum), $signed(neuron_out_next));
                end
                else begin
                    neuron_out_next = biased_sum[DATA_BITS+WEIGHT_BITS-WEIGHT_FRAC_BITS-1 -:DATA_BITS];
                    // $display("[%0t] Linear: Normal output, biased_sum=%d, neuron_out=%d", 
                    //          $time, $signed(biased_sum), $signed(neuron_out_next));
                end
                neuron_out <= neuron_out_next;
            end
        end
        // Otherwise maintain output
    end

endmodule
