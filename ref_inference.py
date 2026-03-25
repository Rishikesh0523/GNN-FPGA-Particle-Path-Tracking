"""Lightweight wrapper around gen_expected for quick checks.

Runs the reference once over a small graph and prints the output norms,
useful when sanity-checking a generator change without going through
the full RTL simulation flow.
"""
import subprocess
import sys


def main():
    print("ref_inference: invoking gen_expected.py with small graph")
    subprocess.check_call([sys.executable, "gen_expected.py"])


if __name__ == "__main__":
    main()
