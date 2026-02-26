"""Validate that mif/ contains the MIFs expected by RTL.

Lists the files actually present vs. the canonical set referenced by
the generated layer files. Useful when iterating on the generator.
"""
import os
import sys

EXPECTED = [
    "ln_gamma_1.mif", "ln_gamma_2.mif", "ln_gamma_3.mif",
    "ln_beta_1.mif",  "ln_beta_2.mif",  "ln_beta_3.mif",
    "test_weights.mif", "test_bias.mif",
]


def main():
    root = "mif"
    missing = [f for f in EXPECTED if not os.path.exists(os.path.join(root, f))]
    extra = [f for f in os.listdir(root) if f not in EXPECTED] if os.path.isdir(root) else []
    if missing:
        print("missing:", missing)
    if extra:
        print("extra:", extra)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
