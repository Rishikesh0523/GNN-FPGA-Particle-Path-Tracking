"""Quick sanity check that all generated MP layer files are present.

Run after gen_layers.py to catch any missed block or layer combination
before kicking off the full simulation.
"""
import os
import sys

NUM_BLOCKS = 8
LAYERS_PER_BLOCK = 3


def main():
    missing = []
    for b in range(NUM_BLOCKS):
        for l in range(1, LAYERS_PER_BLOCK + 1):
            for kind in ("Edge", "Node"):
                f = f"MP_{kind}_Layer_B{b}_L{l}.v"
                if not os.path.exists(f):
                    missing.append(f)
    if missing:
        print("missing:", missing)
        return 1
    print("all", NUM_BLOCKS * LAYERS_PER_BLOCK * 2, "MP layer files present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
