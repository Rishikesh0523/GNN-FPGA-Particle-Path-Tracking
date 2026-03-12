"""Sweep burst sizes against expected encoder throughput.

Reports cycles-per-graph for burst sizes 8/16/32/64 to help pick
the right MAX_BURST_SIZE parameter for bram_burst_wrapper.
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
    for b in (int(x) for x in args.burst_sizes.split(",")):
        print(f"burst={b:3d} cycles={estimate(b):4d}")


if __name__ == "__main__":
    main()
