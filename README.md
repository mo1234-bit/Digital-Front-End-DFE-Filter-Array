# Digital Front-End (DFE) — RTL to ASIC Implementation

> Fractional rate converter → dual IIR notch filters → CIC decimator  
> Python-verified · SystemVerilog RTL · RTL-to-GDS on NanGate 45nm and Sky130

This project implements a Digital Front-End (DFE) signal-processing chain for a software-defined radio receiver. The DFE accepts a 9 MHz sampled input signal, performs fractional rate conversion to 6 MHz, suppresses interference using dual IIR notch filters, and applies a runtime-programmable CIC decimator.

My main work focused on FIR/top-level RTL design and complete ASIC implementation flows using both Synopsys ICC and OpenLane/OpenROAD.

---

## My Contributions

This project was developed as part of a team for the IEEE ISSC Alexandria competition.

My main contributions were:

- Designed and implemented the FIR filter RTL used in the fractional  rate-conversion path — 250-tap Kaiser-window lowpass filter with 72-bit accumulator and configurable coefficient loading.
- Designed and implemented the SPI-controlled register file, enabling runtime-programmable control of the CIC decimation ratio and filter configuration via SPI interface.
- Wrote and integrated the top-level RTL connecting the fractional rate converter, IIR notch filters, CIC decimator, asynchronous FIFO, and SPI control interfaces.
- Integrated my RTL blocks with team-developed DSP blocks, including the dual IIR notch filters and CIC decimator.
- Verified the FIR/fractional-decimation datapath against a Python floating-point/fixed-point reference model.
- Performed the full ASIC implementation flow using Synopsys ICC on NanGate 45nm — synthesis, floorplanning, placement, CTS, routing, STA, DRC, LVS, and sign-off reporting.
- Performed the full ASIC implementation flow using OpenLane/OpenROAD on Sky130 — synthesis, floorplanning, placement, CTS, routing, STA, DRC, LVS, and GDS generation.
- Contributed to timing/debug closure, physical verification, and final sign-off documentation.

The project placed 4th out of 9 teams in the main IEEE ISSC Alexandria competition track and won the ASIC tape-out side prize.

---

## Key Results

| Item | Result |
|---|---|
| Signal chain | Fractional decimator + dual IIR notch + CIC decimator |
| Input sample rate | 9 MHz |
| Fractional conversion | 9 MHz ×2 ÷3 = 6 MHz |
| Data format | 32-bit signed fixed-point, s16.15 |
| FIR filter | 250 taps, Kaiser window, ≥81 dB stopband attenuation |
| IIR notch filters | 2.4 MHz and 5 MHz interference suppression |
| CIC decimator | 4th order, runtime-programmable D = 1–16 |
| CDC | Gray-code asynchronous FIFO |
| NanGate 45nm | Synopsys ICC RTL-to-GDS, timing clean, DRC/LVS clean |
| Sky130 | OpenROAD/OpenLane RTL-to-GDS, WNS +4.09 ns, WHS +0.08 ns, DRC/LVS clean |
| Competition result | ASIC tape-out side prize winner, 4th place in main IEEE ISSC Alexandria competition track |

---

## System Architecture

```text
Input 9 MHz
    │
    ▼
┌─────────────────────────────────────────────────────┐
│  UPSAMPLE ×2  →  FIR 250-tap  →  DOWNSAMPLE ÷3     │
│              Fractional Rate Converter              │
└──────────────────────────┬──────────────────────────┘
                           │
                           │ 6 MHz
                           ▼
             Gray-code Asynchronous FIFO
                           │
                           ▼
┌─────────────────────────────────────────────────────┐
│  IIR NOTCH 2.4 MHz  →  IIR NOTCH 5 MHz              │
│  CIC DECIMATOR, order 4, D = 1 … 16                 │
└─────────────────────────────────────────────────────┘
    │
    ▼
Output 6/D MHz
```

The design operates across two clock domains:

- `clk` domain: high-rate fractional conversion path.
- `clk_1` domain: lower-rate IIR notch filtering and CIC decimation path.

A valid-signal handshake propagates through the datapath so each block only processes real samples when valid data is available.

---

## Signal Processing Blocks

### Fractional Rate Converter

The fractional rate converter converts the input sample rate from 9 MHz to 6 MHz using an upsample-filter-downsample structure:

```text
9 MHz ×2 → 18 MHz → FIR anti-alias filter → ÷3 → 6 MHz
```

Implemented blocks:

- `Interpolation.sv` — inserts zero samples for ×2 upsampling.
- `FIR.sv` — 250-tap anti-alias lowpass FIR filter.
- `Decimator.sv` — keeps every third FIR output sample.

### FIR Filter

The FIR filter is a 250-tap fixed-point lowpass filter.

| Parameter | Value |
|---|---|
| Taps | 250 |
| Window | Kaiser |
| Stopband attenuation | ≥81 dB |
| Passband edge | 2.8 MHz |
| Stopband edge | 3.2 MHz |
| Coefficient format | s16.15 |
| Accumulator width | 72 bits |

The FIR filter is implemented using a highly parallel architecture to maximize throughput and simplify timing closure.

### Asynchronous FIFO

A Gray-code asynchronous FIFO bridges the `clk` and `clk_1` domains.

| Parameter | Value |
|---|---|
| Depth | 16 entries |
| Data width | 32 bits |
| Write clock | `clk` |
| Read clock | `clk_1` |
| CDC style | Gray-code pointers + 2FF synchronizers |

### Dual IIR Notch Filters

Two second-order IIR notch filters are cascaded to suppress interfering tones.

| Stage | Frequency | Notes |
|---|---:|---|
| Stage 1 | 2.4 MHz | Direct notch target |
| Stage 2 | 5.0 MHz | Discrete-time / alias-domain suppression |

> The 5 MHz interferer is represented in the 6 MHz sampled domain through its discrete-time equivalent / alias component.

### CIC Decimator

The CIC block is a 4th-order Cascaded Integrator-Comb decimator with runtime-programmable decimation ratio.

| Parameter | Value |
|---|---|
| Order | 4 |
| Decimation ratio | D = 1–16 |
| Input width | 32 bits |
| Internal width | 48 bits |

---

## Fixed-Point Arithmetic

All data paths use fixed-point arithmetic.

| Signal / Coefficient | Format | Bits |
|---|---|---:|
| Input / output samples | s16.15 | 32 |
| FIR coefficients | s16.15 | 32 |
| FIR accumulator | Extended | 72 |
| IIR coefficients | S1.30 | 32 |
| IIR multiplier intermediates | Signed | 64 |
| CIC internal registers | Extended | 48 |

---

## Python Verification

The Python script acts as both:

- A golden reference model.
- A testbench stimulus generator.

### Verification Flow

```text
1. Generate multi-tone input signal at 9 MHz
2. Design FIR coefficients using scipy.signal
3. Model the full DFE chain in Python
4. Quantize samples and coefficients to fixed-point
5. Generate RTL input files
6. Run RTL simulation
7. Compare RTL output against Python reference
8. Report SNR, error metrics, correlation, and FFT overlays
```

### Test Signal

The test signal combines multiple tones to exercise passband behavior, notch filtering, and decimation behavior.

| Tone | Frequency | Expected Behavior |
|---|---:|---|
| f1 | 400 kHz | Passed |
| f2 | 700 kHz | Passed |
| f3 | 1.0 MHz | Passed |
| f4 | 1.2 MHz | Passed |
| f5 | 2.4 MHz | Notched |
| f6 | 5.0 MHz | Notched / alias-domain suppression |

### Accuracy Metrics

The comparison script reports:

- SNR.
- Maximum absolute error.
- RMS error.
- Normalized cross-correlation.
- FFT comparison between Python and RTL outputs.

---

## ASIC Implementation Summary

### NanGate 45nm — Synopsys ICC

> NanGate 45nm results represent academic RTL-to-GDS implementation, not measured silicon.

| Metric | Result |
|---|---:|
| Toolchain | Synopsys DC + ICC |
| Target frequency | 166 MHz |
| Setup slack | +1.04 ns |
| Hold violations | 0 after CTS |
| DRC | Clean |
| LVS | Passed |
| IR drop VDD / VSS | 12.45 mV / 12.75 mV |
| Total cell area | 991,219 library units |

### Sky130 — OpenROAD/OpenLane

| Metric | Result |
|---|---:|
| Toolchain | Yosys + OpenROAD/OpenLane |
| Target frequency | 71.4 MHz |
| Setup slack | +4.09 ns |
| Hold slack | +0.08 ns |
| TNS | 0.00 ns |
| DRC | Clean |
| LVS | Passed |
| Antenna violations | 0 |
| Total power | 633 mW typical |
| Design area | 5.05 mm² |

---

## Technology Comparison

| Metric | NanGate 45nm ICC | Sky130 OpenROAD |
|---|---:|---:|
| Target frequency | 166 MHz | 71.4 MHz |
| Worst setup slack | +1.04 ns | +4.09 ns |
| Worst hold slack | 0 violations | +0.08 ns |
| TNS | 0.00 ns | 0.00 ns |
| DRC | Clean | Clean |
| LVS | Passed | Passed |
| Approximate area | ~0.30 mm² | ~5.05 mm² |
| Voltage | 1.1 V | 1.8 V |
| Toolchain | Synopsys DC + ICC | Yosys + OpenROAD/OpenLane |
| PDK / library | NanGate 45nm | SkyWater Sky130 |

---

## How to Run

### Python Reference Model

```bash
pip install numpy scipy matplotlib
python Fractional_Decimation_.py
```

Generated files:

```text
stimulus_input.txt
coeffs.hex
python_output.txt
```

### RTL Simulation

Example using Icarus Verilog:

```bash
iverilog -g2012 -o dfe_sim FIR_IIR.sv tb_FIR_IIR.sv
vvp dfe_sim
```

Expected output:

```text
verilog_output.txt
```

### Output Comparison

Run the Python comparison flow after RTL simulation:

```bash
python Fractional_Decimation_.py
```

The script reports:

- SNR.
- Maximum error.
- RMS error.
- Cross-correlation.
- FFT overlays.

---

## Repository Structure

```text
Digital-Front-End-DFE-Filter-Array/
│
├── Design/                    # RTL design files
│   ├── Interpolation.sv       # ×2 upsampler
│   ├── FIR.sv                 # 250-tap Kaiser lowpass FIR filter
│   ├── Decimator.sv           # ÷3 downsampler
│   ├── FIFO.sv                # Gray-code async FIFO (CDC bridge)
│   ├── IIR.sv                 # Second-order IIR notch filter
│   ├── IIR_top.sv             # Dual IIR cascade (2.4 MHz + 5 MHz)
│   ├── CIC.sv                 # 4th-order CIC decimator, D=1–16
│   ├── SPI_reg_file.sv        # SPI-controlled register file
│   └── FIR_IIR.sv             # Top-level integration
│
├── Python/                    # Python reference model and verification
│   ├── Fractional_Decimation_.py  # Golden model + RTL comparison
│   ├── stimulus_input.txt     # Generated test stimulus
│   ├── coeffs.hex             # FIR coefficient file
│   └── python_output.txt      # Python reference output
│
├── ASIC/                      # ASIC implementation results
│   ├── NanGate45/             # Synopsys ICC flow — 166 MHz
│   │   ├── reports/           # Timing, area, DRC, LVS reports
│   │   └── ...
│   └── Sky130/                # OpenLane flow — 71.4 MHz
│       ├── reports/           # Timing, area, DRC, LVS reports
│       └── ...
│
├── LICENSE
└── README.md
```

---

## Limitations and Future Work

- The DFE was verified using Python reference comparison and RTL simulation; larger randomized fixed-point regression could further improve confidence.
- The FIR implementation is fully parallel and area-heavy; future work could explore folded or time-multiplexed FIR architectures.
- Sky130 power is dominated by combinational logic in the 250-tap FIR path; future work includes clock gating and coefficient-symmetry optimization.
- The CDC path uses a Gray-code asynchronous FIFO; additional formal CDC verification is planned.
- NanGate 45nm flow represents academic RTL-to-GDS implementation, not measured silicon.
- Sky130 implementation achieved clean DRC/LVS and competition tape-out readiness, but measured post-silicon results are not included here.

---

## Keywords

`Digital Front-End` `DFE` `SystemVerilog` `DSP` `Fixed-Point` `FIR Filter` `IIR Notch Filter` `CIC Decimator` `Clock Domain Crossing` `Asynchronous FIFO` `ASIC Design` `RTL-to-GDS` `OpenROAD` `OpenLane` `Sky130` `NanGate45` `Synopsys ICC` `Python Verification` `Digital IC Design`
