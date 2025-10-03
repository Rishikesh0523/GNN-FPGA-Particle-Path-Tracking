"""Generate fixed-point gamma/beta initialization streams for layer norm.

Outputs one .mif per layer to mif/. Values quantized to Q1.7.
"""

import os
import math

OUT_DIR = "mif"
LAYERS = 3
WIDTH = 32


def quant(x, frac=7):
    return int(round(x * (1 << frac))) & 0xFF


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for layer in range(1, LAYERS + 1):
        with open(f"{OUT_DIR}/ln_gamma_{layer}.mif", "w") as f:
            for _ in range(WIDTH):
                f.write(f"{quant(1.0):02X}\n")
        with open(f"{OUT_DIR}/ln_beta_{layer}.mif", "w") as f:
            for _ in range(WIDTH):
                f.write(f"{quant(0.0):02X}\n")


if __name__ == "__main__":
    main()
