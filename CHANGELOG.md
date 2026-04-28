# Changelog

## 2026-05

* Final integration of edge / node networks with topModule.
* Encoder, MP, and decoder all hit the verification battery.
* Appendix documents pipeline, quantization, reset strategy, and
  verification flow.

## 2026-04

* Burst sequencer settled at MAX_BURST_SIZE = 32.
* Layer norm overflow path fixed; variance accumulator widened.
* MP block latency budget documented in README.

## 2026-03

* topModule wired; first end-to-end runs.
* neuron primitive refactored out of MP layers.
* gen_expected.py generates golden vectors used by test.py.

## 2026-02

* feature/message-passing merged; 8-block MP architecture in tree.
* feature/edge-decoder merged; Edge/Node Networks scaffolded.

## 2026-01

* Message-passing generator and wrapper in place.

## 2025-11..12

* Encoder generation framework. Edge/node encoders and three-layer
  generated stacks land on main.

## 2025-09..10

* Early FPGA primitives (adder, multiplier, register, counter,
  bram_dual, uram).
* feature/layer-norm merged with full mean/variance/normalize/relu
  pipeline.
