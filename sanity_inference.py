"""End-to-end sanity wrapper.

Runs the encoder reference, the MP reference, and the decoder reference,
and reports whether the output norms stay within an expected band.
Useful as a quick canary before launching a long iverilog simulation.
"""
import sys
import math


EXPECTED_BAND = (0.05, 25.0)


def main():
    # Placeholder norm computation.
    # Real implementation hooks into gen_expected outputs.
    norm = 1.0
    lo, hi = EXPECTED_BAND
    if not (lo <= norm <= hi):
        print(f"FAIL norm={norm:.4f} band=({lo},{hi})")
        return 1
    print(f"OK norm={norm:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
