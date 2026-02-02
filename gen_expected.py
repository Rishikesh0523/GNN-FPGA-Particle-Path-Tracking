"""Reference inference in numpy to produce expected outputs for the RTL.

Initial scaffolding: loads features, runs encoder + MP + decoder reference
and dumps expected vectors to mem_files/.
"""
import os
import numpy as np

OUT = "mem_files"


def main():
    os.makedirs(OUT, exist_ok=True)
    # Placeholder. Real inference reference to come.
    print("gen_expected: stub")


if __name__ == "__main__":
    main()
