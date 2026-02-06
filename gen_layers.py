#!/usr/bin/env python3
"""
gen_mp_node_layer.py
Generates MP_Node_Layer_BX_LY.v files with integrated layer norm.

Configure LAYERS list below, then run:
    python gen_mp_node_layer.py
"""

import os

# -----------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------
OUTPUT_DIR = "./"

# Edge network layers: L1 has 192 input features (6 x 32-feature concat)
#                      L2, L3 have 32 input features
# Node network layers: L1 has 128 input features (4 x 32-feature concat)
#                      L2, L3 have 32 input features
EDGE_L1_FEATURES = 192
NODE_L1_FEATURES = 128
L2_L3_FEATURES   = 32

def make_layers(net_type):
    # net_type: 'edge' or 'node'
    l1_feat = EDGE_L1_FEATURES if net_type == "edge" else NODE_L1_FEATURES
    prefix  = "mp_edge" if net_type == "edge" else "mp_node"
    layers  = []
    for block in range(8):
        for layer, feats in enumerate([l1_feat, L2_L3_FEATURES, L2_L3_FEATURES], start=1):
            layers.append({
                "block"   : block,
                "layer"   : layer,
                "neurons" : 32,
                "features": feats,
                "net_type": net_type,
                "prefix"  : prefix,
            })
    return layers

DEFAULTS = {
    "prefix"           : "mp_node",  # prefix for weight/bias MIF files
    "data_bits"        : 8,
    "weight_bits"      : 8,
    "bias_bits"        : 8,
    "done_delay"       : 2,        # cycles to wait after counter_done
    # RMS norm
    "ln_data_bits"     : 24,
    "ln_data_frac_bits": 10,
    "ln_scale_bits"    : 8,
    "ln_frac_bits"     : 6,
    "ln_inv_sqrt_bits" : 16,
    "ln_inv_sqrt_frac" : 11,
    "ln_var_bits"      : 45,
    "ln_lut_bits"      : 5,
    "ln_lut_size"      : 20,
    "ln_epsilon"       : 1,
    "ln_out_bits"      : 8,
    "ln_out_frac_bits" : 4,
}

# -----------------------------------------------------------------------
# Helper
# -----------------------------------------------------------------------
def cfg(layer_dict, key):
    return layer_dict.get(key, DEFAULTS[key])

# -----------------------------------------------------------------------
# Single neuron instance
# -----------------------------------------------------------------------
def gen_neuron_instance(n, cfg_d):
    prefix      = cfg(cfg_d, "prefix")
    block       = cfg_d["block"]
    layer       = cfg_d["layer"]
    num_features= cfg_d["features"]

    weight_file = f"{prefix}_w_{block}_{layer}_{n}.mif"
    bias_file   = f"{prefix}_b_{block}_{layer}_{n}.mif"

    return f"""
        if (NUM_NEURONS > {n}) begin : neuron_{n}
            neuron #(
                .NEURON_WIDTH(NUM_FEATURES),
                .DATA_BITS   (DATA_BITS),
                .WEIGHT_BITS (WEIGHT_BITS),
                .BIAS_BITS   (BIAS_BITS),
                .WeightFile  ("{weight_file}"),
                .BiasFile    ("{bias_file}")
            ) inst (
                .clk                (clk),
                .rstn               (rstn),
                .activation_function(activation_function),
                .data_in_flat       (data_in_flat),
                .counter            (counter),
                .data_out           (neuron_outputs[{n}])
            );
        end
"""

# -----------------------------------------------------------------------
# Full module
# -----------------------------------------------------------------------
def gen_module(cfg_d):
    block       = cfg_d["block"]
    layer       = cfg_d["layer"]
    num_neurons = cfg_d["neurons"]
    num_features= cfg_d["features"]
    prefix      = cfg(cfg_d, "prefix")
    done_delay  = cfg(cfg_d, "done_delay")

    data_bits        = cfg(cfg_d, "data_bits")
    weight_bits      = cfg(cfg_d, "weight_bits")
    bias_bits        = cfg(cfg_d, "bias_bits")
    ln_data_bits     = cfg(cfg_d, "ln_data_bits")
    ln_data_frac_bits= cfg(cfg_d, "ln_data_frac_bits")
    ln_scale_bits    = cfg(cfg_d, "ln_scale_bits")
    ln_frac_bits     = cfg(cfg_d, "ln_frac_bits")
    ln_inv_sqrt_bits = cfg(cfg_d, "ln_inv_sqrt_bits")
    ln_inv_sqrt_frac = cfg(cfg_d, "ln_inv_sqrt_frac")
    ln_var_bits      = cfg(cfg_d, "ln_var_bits")
    ln_lut_bits      = cfg(cfg_d, "ln_lut_bits")
    ln_lut_size      = cfg(cfg_d, "ln_lut_size")
    ln_epsilon       = cfg(cfg_d, "ln_epsilon")
    ln_out_bits      = cfg(cfg_d, "ln_out_bits")
    ln_out_frac_bits = cfg(cfg_d, "ln_out_frac_bits")

    net_type    = cfg_d.get("net_type", "edge")
    prefix_name = "MP_Edge_Layer" if net_type == "edge" else "MP_Node_Layer"
    module_name = f"{prefix_name}_B{block}_L{layer}"

    # Gamma is shared across all blocks for a given layer number.
    gamma_file  = f"ln_gamma_{layer}.mif"

    # Validate: counter uses NUM_FEATURES/4; fractional result would be silently wrong
    assert num_features % 4 == 0, (
        f"{module_name}: NUM_FEATURES={num_features} must be divisible by 4 "
        f"(counter parameter END_COUNTER = NUM_FEATURES/4)"
    )

    neuron_instances = "".join(
        gen_neuron_instance(n, cfg_d)
        for n in range(num_neurons)
    )

    # delay counter width: minimum 2 bits, just enough to count to done_delay
    delay_bits = max(2, int(done_delay).bit_length() + 1)

    verilog = f"""`timescale 1ns / 1ps
//==============================================================================
// {module_name}.v  --  Auto-generated by gen_layers.py
//
// Block {block}, Layer {layer}
// {num_features} inputs -> {num_neurons} neurons -> rms norm -> {num_neurons} x {ln_out_bits}-bit Q4.4 outputs
//==============================================================================
module {module_name} #(
    parameter LAYER_NO        = {layer},
    parameter BLOCK_NO        = {block},
    parameter NUM_NEURONS     = {num_neurons},
    parameter NUM_FEATURES    = {num_features},
    parameter DATA_BITS       = {data_bits},
    parameter WEIGHT_BITS     = {weight_bits},
    parameter BIAS_BITS       = {bias_bits},
    // RMS norm
    parameter LN_DATA_BITS      = {ln_data_bits},
    parameter LN_DATA_FRAC_BITS = {ln_data_frac_bits},
    parameter LN_SCALE_BITS     = {ln_scale_bits},
    parameter LN_FRAC_BITS      = {ln_frac_bits},
    parameter LN_INV_SQRT_BITS  = {ln_inv_sqrt_bits},
    parameter LN_INV_SQRT_FRAC  = {ln_inv_sqrt_frac},
    // LN_VAR_BITS derivation: rms = sum of NUM_NEURONS squared LN_DATA_BITS values.
    //   squared term : LN_DATA_BITS*2 = {ln_data_bits*2} bits
    //   sum of {num_neurons}  : +clog2({num_neurons}) = +{(num_neurons-1).bit_length()} bits  -> {ln_data_bits*2 + (num_neurons-1).bit_length()} bits needed
    //   LN_VAR_BITS = {ln_var_bits} provides margin above that.
    parameter LN_VAR_BITS       = {ln_var_bits},
    parameter LN_LUT_BITS       = {ln_lut_bits},
    parameter LN_LUT_SIZE       = {ln_lut_size},
    parameter LN_EPSILON        = {ln_epsilon},
    parameter LN_OUT_BITS       = {ln_out_bits},
    parameter LN_OUT_FRAC_BITS  = {ln_out_frac_bits},
    parameter USE_RMS_NORM    = 1,
    parameter GammaFile         = "{gamma_file}"
)(
    input  clk,
    input  rstn,
    input  activation_function,
    input  start,
    input  signed [NUM_FEATURES*DATA_BITS-1:0]   data_in_flat,

    output signed [NUM_NEURONS*LN_OUT_BITS-1:0]  data_out_flat,  // Q4.4 per neuron
    output valid_out,                                          // layer norm done
    output done
);

    //--------------------------------------------------------------------------
    // Neuron output width
    //--------------------------------------------------------------------------
    localparam NEURON_OUT_BITS = DATA_BITS + WEIGHT_BITS + 8;

    //--------------------------------------------------------------------------
    // Counter: .rstn(start) keeps counter at 0 until start asserted.
    // Works correctly with held start signals (layer1_held/layer2_held/layer3_held
    // stay HIGH for the full computation duration).
    wire [31:0] counter;
    wire        counter_done;

    counter #(
        .END_COUNTER(NUM_FEATURES/4)
    ) layer_counter (
        .clk               (clk),
        .rstn              (start),
        .counter_out       (counter),
        .counter_donestatus(counter_done)
    );

    //--------------------------------------------------------------------------
    // Computation active + done state machine
    //
    // computation_active is cleared when done_reg is set so that the
    // first branch (start && !computation_active && !done_reg) can fire
    // correctly on every new edge, not just the very first one.
    //--------------------------------------------------------------------------
    reg computation_active;
    reg done_reg;
    reg [{delay_bits-1}:0] done_delay_counter;  // {delay_bits} bits: counts 0..{done_delay}

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            computation_active <= 0;
            done_reg           <= 0;
            done_delay_counter <= 0;
        end else begin
            if (start && !computation_active && !done_reg) begin
                // Fresh start: arm and begin counting
                computation_active <= 1;
                done_reg           <= 0;
                done_delay_counter <= 0;
            end else if (counter_done && computation_active && !done_reg) begin
                if (done_delay_counter < {done_delay}) begin
                    done_delay_counter <= done_delay_counter + 1;
                    done_reg           <= 0;
                end else begin
                    // Computation complete: set done, clear active so next
                    // start pulse can re-enter the first branch cleanly
                    done_reg           <= 1;
                    computation_active <= 0;
                    done_delay_counter <= 0;
                end
            end else if (done_reg && !start) begin
                // Wait for the parent to drop start after valid_out before re-arming.
                done_reg           <= 0;
                done_delay_counter <= 0;
            end
        end
    end

    assign done = done_reg;

    //--------------------------------------------------------------------------
    // Raw neuron outputs
    //--------------------------------------------------------------------------
    wire signed [NEURON_OUT_BITS-1:0] neuron_outputs [0:NUM_NEURONS-1];

    //--------------------------------------------------------------------------
    // Layer norm input bus
    //--------------------------------------------------------------------------
    reg signed [NUM_NEURONS*LN_DATA_BITS-1:0] ln_data_in;

    //--------------------------------------------------------------------------
    // Gamma -- load from MIF, then assign each slice via generate.
    //--------------------------------------------------------------------------
    reg signed [LN_SCALE_BITS-1:0] gamma_arr [0:NUM_NEURONS-1];

    initial begin
        $readmemb(GammaFile, gamma_arr);
    end

    wire signed [NUM_NEURONS*LN_SCALE_BITS-1:0] ln_gamma;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_NEURONS; gi = gi + 1) begin : ln_param_pack
            assign ln_gamma[gi*LN_SCALE_BITS +: LN_SCALE_BITS] = gamma_arr[gi];
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Edge detect done_reg rising edge -> 1-cycle pulse to layer norm
    // done_reg goes high after the neuron delay, so neurons are stable
    //--------------------------------------------------------------------------
    reg  done_reg_r;
    reg  ln_start;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            done_reg_r <= 1'b0;
            ln_start   <= 1'b0;
        end else begin
            done_reg_r <= done_reg;
            // Rising edge of done_reg = neurons settled, safe to start LN
            ln_start   <= done_reg & ~done_reg_r;
        end
    end

    //--------------------------------------------------------------------------
    // Latch + sign-extend neuron outputs into ln_data_in on ln_start pulse
    //--------------------------------------------------------------------------
    integer n;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ln_data_in <= {{(NUM_NEURONS*LN_DATA_BITS){{1'b0}}}};
        end else if (ln_start) begin
            for (n = 0; n < NUM_NEURONS; n = n + 1) begin
                ln_data_in[n*LN_DATA_BITS +: LN_DATA_BITS] <=
                    {{{{(LN_DATA_BITS-NEURON_OUT_BITS){{neuron_outputs[n][NEURON_OUT_BITS-1]}}}},
                      neuron_outputs[n]}};
            end
        end
    end

    //--------------------------------------------------------------------------
    // RMS norm / bypass
    //--------------------------------------------------------------------------
    generate
        if (USE_RMS_NORM) begin : gen_rms_norm
            rms_norm #(
                .NUM_FEATURES      (NUM_NEURONS),
                .DATA_BITS         (LN_DATA_BITS),
                .DATA_FRAC_BITS    (LN_DATA_FRAC_BITS),
                .SCALE_BITS        (LN_SCALE_BITS),
                .FRAC_BITS         (LN_FRAC_BITS),
                .INV_SQRT_BITS     (LN_INV_SQRT_BITS),
                .INV_SQRT_FRAC_BITS(LN_INV_SQRT_FRAC),
                .VAR_BITS          (LN_VAR_BITS),
                .LUT_BITS          (LN_LUT_BITS),
                .LUT_SIZE          (LN_LUT_SIZE),
                .EPSILON           (LN_EPSILON),
                .OUT_BITS          (LN_OUT_BITS),
                .OUT_FRAC_BITS     (LN_OUT_FRAC_BITS)
            ) u_rms_norm (
                .clk      (clk),
                .rstn     (rstn),
                .valid_in (ln_start),
                .act_en   (activation_function),
                .data_in  (ln_data_in),
                .gamma    (ln_gamma),
                .valid_out(valid_out),
                .busy     (),
                .data_out (data_out_flat)
            );
        end else begin : gen_bypass_rms_norm
            layer_norm_relu #(
                .NUM_FEATURES      (NUM_NEURONS),
                .DATA_BITS         (LN_DATA_BITS),
                .DATA_FRAC_BITS    (LN_DATA_FRAC_BITS),
                .OUT_BITS          (LN_OUT_BITS),
                .OUT_FRAC_BITS     (LN_OUT_FRAC_BITS)
            ) u_rms_norm_bypass (
                .clk      (clk),
                .rstn     (rstn),
                .valid_in (ln_start),
                .act_en   (activation_function),
                .data_in  (ln_data_in),
                .valid_out(valid_out),
                .data_out (data_out_flat)
            );
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Neuron instances
    //--------------------------------------------------------------------------
    generate
{neuron_instances}
    endgenerate

endmodule
"""
    return verilog


# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------
def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--type", choices=["edge", "node", "both"], default="both",
                        help="Which network layers to generate (default: both)")
    parser.add_argument("--outdir", default=OUTPUT_DIR,  # mirrors top-level OUTPUT_DIR
                        help="Output directory (default: current directory)")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    nets = []
    if args.type in ("edge", "both"): nets.append("edge")
    if args.type in ("node", "both"): nets.append("node")

    all_layers = []
    for net in nets:
        all_layers.extend(make_layers(net))

    for layer_cfg in all_layers:
        block       = layer_cfg["block"]
        layer       = layer_cfg["layer"]
        net_type    = layer_cfg.get("net_type", "edge")
        prefix_name = "MP_Edge_Layer" if net_type == "edge" else "MP_Node_Layer"
        module_name = f"{prefix_name}_B{block}_L{layer}"
        filename    = os.path.join(args.outdir, f"{module_name}.v")

        print(f"Generating {module_name}: "
              f"{layer_cfg['features']} features -> "
              f"{layer_cfg['neurons']} neurons -> "
              f"{cfg(layer_cfg, 'ln_out_bits')}-bit Q4.4 output")

        verilog = gen_module(layer_cfg)

        with open(filename, "w", encoding="utf-8") as f:
            f.write(verilog)

        print(f"  Written: {filename}")

    print(f"\nDone. {len(all_layers)} file(s) written to '{args.outdir}/'")


if __name__ == "__main__":
    main()
