"""Initial encoder MIF generator.

Emits placeholder weights for the encoder layers so simulation can
elaborate. Real values come once we have training weights to load.
"""
import os

OUT = "mif"
WIDTH = 32
DEPTH = 32


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(f"{OUT}/test_weights.mif", "w") as f:
        for _ in range(DEPTH):
            f.write("00\n")


if __name__ == "__main__":
    main()
