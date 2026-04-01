"""Sweep burst sizes against expected encoder throughput.

Reports cycles-per-graph for burst sizes 8/16/32/64 and the ratio
against the baseline (32) so it's easy to spot which size is fastest
for a given graph shape.
"""
import argparse


def estimate(burst):
    setup = 4
    beats = max(32 // burst, 1) * burst
    return setup + beats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--burst-sizes", default="8,16,32,64")
    args = ap.parse_args()
    sizes = [int(x) for x in args.burst_sizes.split(",")]
    baseline = estimate(32)
    for b in sizes:
        c = estimate(b)
        ratio = c / baseline
        print(f"burst={b:3d} cycles={c:4d} x{ratio:.2f}")


if __name__ == "__main__":
    main()
