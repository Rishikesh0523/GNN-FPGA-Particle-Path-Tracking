#!/usr/bin/env python3
"""
gen_layers.py
Emits MP_Edge_Layer_BxLy.v and MP_Node_Layer_BxLy.v for the message
passing block. Each block has multiple layers, each layer is a
neuron stack followed by layer norm.

Initial scaffolding: produces stubs so the wrapper can elaborate.
"""

import os
import argparse

NUM_BLOCKS = 8
LAYERS_PER_BLOCK = 3
NUM_NEURONS = 32
DATA_BITS = 8


def emit_stub(kind, b, l, outdir):
    name = f"MP_{kind}_Layer_B{b}_L{l}"
    path = os.path.join(outdir, name + ".v")
    with open(path, "w") as f:
        f.write(f"// Auto-generated stub for {name}\n")
        f.write(f"module {name} ();\n")
        f.write("endmodule\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default=".")
    args = ap.parse_args()
    for b in range(NUM_BLOCKS):
        for l in range(1, LAYERS_PER_BLOCK + 1):
            emit_stub("Edge", b, l, args.outdir)
            emit_stub("Node", b, l, args.outdir)


if __name__ == "__main__":
    main()
