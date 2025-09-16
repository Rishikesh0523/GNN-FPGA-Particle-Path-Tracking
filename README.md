# FPGA Graph Neural Network Accelerator

Verilog RTL and Python tooling for an FPGA-based graph neural network
inference accelerator. The pipeline implements message passing over
edge / node features with BRAM-backed storage and on-chip layer
normalization.

## Layout

| Path                      | Purpose                                |
|---------------------------|----------------------------------------|
| `*.v`                     | Synthesizable RTL                      |
| `gen_*.py`, `makelayers.py` | Python generators for hardware layers |
| `mem_files/`              | Test feature vectors (gitignored)      |
| `mif/`                    | Memory init files for BRAM (gitignored)|
| `appendix.tex`            | Architecture write-up                  |

## Build dependencies

* Vivado 2023.2+ (URAM288 / BRAM18 primitives)
* Python 3.10+ for generator scripts
* numpy for `gen_expected.py`

## Simulation

```
iverilog -g2012 -o sim *.v
vvp sim
```

Memory init files live in `mem_files/` and `mif/` (both gitignored).
