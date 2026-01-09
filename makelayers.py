#!/usr/bin/env python3
"""Helper invocation wrapper around gen_layers.py.

Runs the generator and reports which files were touched.
"""
import subprocess
import sys


def main():
    subprocess.check_call([sys.executable, "gen_layers.py", "--outdir", "."])


if __name__ == "__main__":
    main()
