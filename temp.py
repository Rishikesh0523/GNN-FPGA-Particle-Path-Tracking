"""Sanity checks for layer-norm components against numpy references."""
import math
from lut_generator import gen, LUT_SIZE, FRAC_BITS


def check_inv_sqrt():
    lut = gen()
    for i in range(LUT_SIZE):
        ref = 1.0 / math.sqrt(max(i, 1) / LUT_SIZE)
        got = lut[i] / (1 << FRAC_BITS)
        err = abs(ref - got)
        assert err < 0.05, (i, ref, got, err)
    print("inv_sqrt: OK", LUT_SIZE, "entries")


def check_variance_overflow_room():
    # Worst-case input range
    n = 32
    extra = 8
    max_sq = (1 << 15) ** 2
    assert n * max_sq < (1 << (15 + 15 + extra))
    print("variance: headroom OK")


if __name__ == "__main__":
    check_inv_sqrt()
    check_variance_overflow_room()
