# BRAM / URAM layout

A reference for which bank holds what once the design is on hardware.

## URAM banks

* URAM_0..3 — Edge feature ping-pong buffers (8x32 features)
* URAM_4..7 — Node feature ping-pong buffers (8x32 features)
* URAM_8    — Edge encoder weight cache (per-layer reload)
* URAM_9    — Node encoder weight cache
* URAM_10..17 — MP block weights (1 URAM per block, edge + node interleaved)

## BRAM18 banks

* BRAM_0..1 — Connectivity src / dst tables
* BRAM_2..3 — LN gamma / beta
* BRAM_4    — Decoder weights
* BRAM_5    — Output transform constants

## Notes

* All BRAMs use `RAM_STYLE = ULTRA` where feasible; small ports fall back
  to BRAM18.
* The burst sequencer drives URAMs through `bram_burst_wrapper.v`.

## Address layout (edge buffer, URAM_0)

| Offset      | Field                 |
|-------------|-----------------------|
| 0x000-0x1FF | block 0 edge features |
| 0x200-0x3FF | block 0 scatter sum   |
| 0x400-0x5FF | block 1 edge features |
| ...         | ...                   |

Block stride is `0x200` (2 KB) per block.

## Sizing summary

| Resource        | Used  | Available (XCAU25P) |
|-----------------|-------|----------------------|
| URAM288         | 18    | 64                   |
| BRAM18          | 6     | 300                  |
| DSP48           | ~512  | 1968                 |

DSP usage is dominated by the MP MAC arrays; further reuse is
possible via time-multiplexing across blocks but isn't yet wired up.
