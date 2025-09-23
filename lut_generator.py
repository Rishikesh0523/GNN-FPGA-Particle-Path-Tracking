"""Generate inverse-sqrt LUT values for layer norm.

Initial cut: produce fixed-point reciprocal-square-root entries over a
limited range. Will be hooked into the normalization pipeline once the
variance stage is in place.
"""

import math

LUT_SIZE = 64
FRAC_BITS = 8


def gen():
    return [
        int(round((1.0 / math.sqrt(max(i, 1) / LUT_SIZE)) * (1 << FRAC_BITS)))
        for i in range(LUT_SIZE)
    ]


if __name__ == "__main__":
    for v in gen():
        print(v)
