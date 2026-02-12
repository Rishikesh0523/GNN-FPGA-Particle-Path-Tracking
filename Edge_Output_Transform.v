`timescale 1ns / 1ps

module edge_output_transform
#(
    parameter LAYER_NO        = 2,
    parameter NUM_NEURONS    = 1,
    parameter NUM_FEATURES   = 32,
    parameter DATA_BITS      = 8,
    parameter WEIGHT_BITS    = 8,
    parameter BIAS_BITS      = 8
)
(
    input  clk,
    input  rstn,
    input  activation_function,
    input  start,
    input  signed [NUM_FEATURES*DATA_BITS-1:0] data_in_flat,
    output signed [DATA_BITS-1:0] data_out_flat,
    output done
);

    // Internal counter signals
    wire [31:0] counter;
    wire counter_done;
    reg computation_active;
    // Individual neuron outputs
    wire signed [DATA_BITS+WEIGHT_BITS+8-1:0] neuron_outputs [0:NUM_NEURONS-1];
    // Add a delay register for done signal
    reg done_reg;
    reg [6:0] done_delay_counter;
    
    // Control computation active flag - FIXED STATE MACHINE
    always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        computation_active <= 0;
        done_reg           <= 0;
        done_delay_counter <= 0;
    end else begin
        if (!computation_active && !done_reg) begin
            // First clock after rstn released — start the run
            computation_active <= 1;
            done_delay_counter <= 0;
        end else if (counter_done && computation_active && !done_reg) begin
            if (done_delay_counter < 2) begin
                done_delay_counter <= done_delay_counter + 1;
            end else begin
                done_reg           <= 1;
                done_delay_counter <= 0;
                // Stay in done_reg=1 until rstn drops again (next edge)
                // Do NOT clear done_reg or restart here
            end
        end
        // No else-if for done_reg — let reset handle the restart
    end
end

    assign done = done_reg;

    // Instantiate internal counter
    counter #(
        .END_COUNTER((NUM_FEATURES + 3) / 4)
    ) layer_counter (
        .clk(clk),
        .rstn(rstn),
        .counter_out(counter),
        .counter_donestatus(counter_done)
    );
        
    // Generate neurons
    generate

        // Neuron 0
        if (NUM_NEURONS > 0) begin : neuron_0
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("output_w_2_0.mif"),
                .BiasFile     ("output_b_2_0.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[0])
            );
            assign data_out_flat[0*DATA_BITS +: DATA_BITS] = neuron_outputs[0];
        end

    endgenerate

endmodule
