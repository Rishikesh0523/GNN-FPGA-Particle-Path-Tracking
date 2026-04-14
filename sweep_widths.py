"""Sweep encoder hidden widths and report cycle / BRAM impact.

Currently a stub - prints the candidate widths and the BRAM word
estimate so designers can pick before re-running gen_layers.py.
"""
WIDTHS = [16, 32, 48, 64]
BRAM_WORDS_PER_LAYER = 32


def main():
    for w in WIDTHS:
        words = BRAM_WORDS_PER_LAYER * w
        urams = max(1, words // 4096)
        print(f"width={w:3d} words={words:5d} urams={urams}")


if __name__ == "__main__":
    main()
