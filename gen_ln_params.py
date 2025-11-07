#!/usr/bin/env python3
"""
gen_ln_params.py
Generates random gamma and beta MIF files for layer norm.

Configure LAYERS list below, then run:
    python gen_ln_params.py
"""

import os
import random

# -----------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------

OUTPUT_DIR  = "./mif"
SCALE_BITS  = 8        # must match LN_SCALE_BITS in Verilog
SEED        = 42       # set to None for truly random each run

# Each dict defines one set of LN param files to generate
# Keys: prefix, block (optional), layer, neurons
LAYERS = [
    # edge_encoder style  -> ln_gamma_edge_encoder_1.mif / ln_beta_edge_encoder_1.mif
    {"prefix": "edge_encoder", "layer": 1, "neurons": 32},
    {"prefix": "edge_encoder", "layer": 2, "neurons": 64},
    {"prefix": "edge_encoder", "layer": 3, "neurons": 32},
    # {"prefix": "edge_encoder", "layer": 4, "neurons": 16},

    # # mp_node style       -> ln_gamma_mp_node_1_3.mif / ln_beta_mp_node_1_3.mif
    # {"prefix": "mp_node", "block": 1, "layer": 3, "neurons": 32},
    # {"prefix": "mp_node", "block": 1, "layer": 4, "neurons": 32},
    # {"prefix": "mp_node", "block": 2, "layer": 3, "neurons": 64},
]

# -----------------------------------------------------------------------
# Filename helpers — match exactly what the Verilog modules expect
# -----------------------------------------------------------------------
def gamma_filename(cfg):
    if "block" in cfg:
        return f"ln_gamma_{cfg['block']}_{cfg['layer']}.mif"
    else:
        return f"ln_gamma_{cfg['layer']}.mif"

def beta_filename(cfg):
    if "block" in cfg:
        return f"ln_beta_{cfg['prefix']}_{cfg['block']}_{cfg['layer']}.mif"
    else:
        return f"ln_beta_{cfg['layer']}.mif"

# -----------------------------------------------------------------------
# Write one MIF file — NUM_NEURONS lines of SCALE_BITS binary digits
# Values are signed 8-bit: range [-128, 127]
# For gamma: bias toward positive values (0 to 127) so scale doesn't flip sign
# For beta:  full signed range (-128 to 127)
# -----------------------------------------------------------------------
def write_mif(filepath, num_neurons, signed_range=True, positive_only=False):
    with open(filepath, "w", encoding="utf-8") as f:
        for _ in range(num_neurons):
            if positive_only:
                # gamma: keep positive so normalization doesn't invert
                val = random.randint(1, (2**(SCALE_BITS-1)) - 1)   # 1 to 127
            else:
                # beta: full signed range
                val = random.randint(-(2**(SCALE_BITS-1)), (2**(SCALE_BITS-1)) - 1)

            # Convert to unsigned two's complement for binary representation
            if val < 0:
                val_bits = val + (1 << SCALE_BITS)   # two's complement
            else:
                val_bits = val

            f.write(f"{val_bits:0{SCALE_BITS}b}\n")

# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------
def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    if SEED is not None:
        random.seed(SEED)
        print(f"Random seed: {SEED}")
    else:
        print("Random seed: none (different every run)")

    print(f"SCALE_BITS = {SCALE_BITS}")
    print(f"Output dir : {OUTPUT_DIR}\n")

    for layer_cfg in LAYERS:
        neurons = layer_cfg["neurons"]

        gfile = os.path.join(OUTPUT_DIR, gamma_filename(layer_cfg))
        bfile = os.path.join(OUTPUT_DIR, beta_filename(layer_cfg))

        write_mif(gfile, neurons, positive_only=True)   # gamma: positive only
        write_mif(bfile, neurons, positive_only=False)  # beta:  full range

        print(f"  {os.path.basename(gfile):<45}  {neurons} entries  (gamma, positive)")
        print(f"  {os.path.basename(bfile):<45}  {neurons} entries  (beta,  signed)")

    print(f"\nDone. {len(LAYERS)*2} file(s) written to '{OUTPUT_DIR}/'")


if __name__ == "__main__":
    main()