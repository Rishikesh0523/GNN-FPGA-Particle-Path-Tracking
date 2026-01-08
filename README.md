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

## Memory layout

BRAM bank assignment (current target: XCAU25P):

| Bank        | Purpose                                |
|-------------|----------------------------------------|
| URAM 0..3   | Edge feature ping-pong buffers         |
| URAM 4..7   | Node feature ping-pong buffers         |
| BRAM18 0..1 | Connectivity src/dst tables            |
| BRAM18 2..3 | Layer-norm gamma / beta MIF storage    |

Burst sequencer (`BRAM_burst_read_data_ss.v`) streams 32-beat windows
to the encoder pipeline.
