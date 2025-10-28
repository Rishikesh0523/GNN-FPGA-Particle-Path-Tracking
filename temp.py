"""Quick sanity check for inv-sqrt LUT against numpy."""
import math
from lut_generator import gen, LUT_SIZE, FRAC_BITS


def main():
    lut = gen()
    for i in range(LUT_SIZE):
        ref = 1.0 / math.sqrt(max(i, 1) / LUT_SIZE)
        got = lut[i] / (1 << FRAC_BITS)
        err = abs(ref - got)
        assert err < 0.05, (i, ref, got, err)
    print("OK", LUT_SIZE, "entries")


if __name__ == "__main__":
    main()
