#!/usr/bin/env python3
"""
Generate Verilog node_encoder_layer module with 32 neurons and internal counter
"""

def generate_layer_module(num_features=32, num_neurons=32, block_no=1, layer_no=1):
    code = f"""`timescale 1ns / 1ps

module MP_Node_Layer_B{block_no}_L{layer_no}
#(
    parameter LAYER_NO       = {layer_no},
    parameter NUM_NEURONS    = {num_neurons},
    parameter NUM_FEATURES   = {num_features},
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
    output signed [NUM_NEURONS*DATA_BITS-1:0] data_out_flat,
    output valid_out
);

    // Internal counter signals
    // FIX: counter uses module rstn (not start) so it is NOT reset when
    // start goes low mid-computation. This enables inter-edge pipelining:
    // start is a held signal from the compute FSM and can go low between
    // edges without disturbing in-flight computation.
    wire [31:0] counter;
    wire counter_done;
    reg computation_active;
    // Individual neuron outputs
    wire signed [DATA_BITS-1:0] neuron_outputs [0:NUM_NEURONS-1];
    reg valid_reg;
    reg [6:0] done_delay_counter;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            computation_active <= 0;
            valid_reg <= 0;
            done_delay_counter <= 0;
        end else begin
            if (start && !computation_active && !valid_reg) begin
                computation_active <= 1;
                valid_reg <= 0;
                done_delay_counter <= 0;
            end else if (counter_done && computation_active && !valid_reg) begin
                if (done_delay_counter < 1) begin
                    done_delay_counter <= done_delay_counter + 1;
                    valid_reg <= 0;
                end else begin
                    valid_reg <= 1;
                    done_delay_counter <= 0;
                end
            end else if (valid_reg && start) begin
                // Restart for next edge
                computation_active <= 1;
                valid_reg <= 0;
                done_delay_counter <= 0;
            end
        end
    end

    assign valid_out = valid_reg;

    // FIX: counter rstn = module rstn, not start
    // This allows the counter to keep running even when start drops low
    // between consecutive edges in the pipeline.
    counter #(
        .END_COUNTER(NUM_FEATURES)
    ) layer_counter (
        .clk(clk),
        .rstn(rstn),
        .counter_out(counter),
        .counter_donestatus(counter_done)
    );
        
    // Generate neurons
    generate
"""
    
    # Generate each neuron
    for i in range(num_neurons):
        code += f"""
        // Neuron {i}
        if (NUM_NEURONS > {i}) begin : neuron_{i}
            neuron #(
                .NEURON_WIDTH (NUM_FEATURES),
                .DATA_BITS    (DATA_BITS),
                .WEIGHT_BITS  (WEIGHT_BITS),
                .BIAS_BITS    (BIAS_BITS),
                .WeightFile   ("mp_node_w_{block_no}_{layer_no}_{i}.mif"),
                .BiasFile     ("mp_node_b_{block_no}_{layer_no}_{i}.mif")
            ) inst (
                .clk                 (clk),
                .rstn                (rstn),
                .activation_function (activation_function),
                .data_in_flat        (data_in_flat),
                .counter             (counter),
                .data_out            (neuron_outputs[{i}])
            );
            assign data_out_flat[{i}*DATA_BITS +: DATA_BITS] = neuron_outputs[{i}];
        end
"""
    
    code += """
    endgenerate

endmodule
"""
    
    return code

if __name__ == "__main__":
    import os, argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--type", choices=["node", "edge"], default="node",
                        help="node: MP_Node_Layer (128->32->32)  edge: MP_Edge_Layer (192->32->32)")
    parser.add_argument("--outdir", default=".", help="output directory")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    # Layer 1 input width differs between node and edge networks
    l1_features = 128 if args.type == "node" else 192
    prefix      = "MP_Node_Layer" if args.type == "node" else "MP_Edge_Layer"

    layer_features = {1: l1_features, 2: 32, 3: 32}

    for block_no in range(8):           # blocks 0–7
        for layer_no in range(1, 4):    # layers 1, 2, 3
            nf = layer_features[layer_no]
            code = generate_layer_module(
                num_features=nf,
                num_neurons=32,
                block_no=block_no,
                layer_no=layer_no
            )
            # Rename module to match prefix
            code = code.replace(
                f"MP_Node_Layer_B{block_no}_L{layer_no}",
                f"{prefix}_B{block_no}_L{layer_no}"
            )
            # Edge layers: output port is valid_out (already generated that way)
            fname = os.path.join(args.outdir, f"{prefix}_B{block_no}_L{layer_no}.v")
            with open(fname, "w") as f:
                f.write(code)
            print(f"Generated {fname}  (num_features={nf})")