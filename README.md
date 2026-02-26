# Digital Front-End (DFE) — ASIC Implementation

> **Fractional rate converter → Dual IIR notch filters → CIC decimator**  
> Verified in Python · Implemented in SystemVerilog · Taped out on NanGate 45nm (ICC) and Sky130 130nm (OpenROAD)

---


## 1. Project Overview

This project implements a complete **Digital Front-End (DFE)** signal-processing chain for a software-defined radio receiver. The chain accepts a 9 MHz sampled signal and delivers a decimated, interference-free output at a programmable rate. All DSP blocks are designed in SystemVerilog, numerically verified against a Python floating-point reference, and silicon-proven on two technology nodes.

```
Input 9 MHz
    │
    ▼
┌─────────────────────────────────────────────────────┐  clk domain (166 MHz / NanGate │ 71 MHz / Sky130)
│  UPSAMPLE ×2  →  FIR 250-tap  →  DOWNSAMPLE ÷3     │
│              (Fractional Decimator 2/3)              │
└──────────────────────────┬──────────────────────────┘
                           │  6 MHz   [Gray-code Async FIFO — CDC]
┌──────────────────────────▼──────────────────────────┐  clk_1 domain (55 MHz / NanGate │ lower rate / Sky130)
│  IIR NOTCH (2.4 MHz)  →  IIR NOTCH (5 MHz)         │
│  CIC DECIMATOR  (order-4, D = 1 … 16)               │
└─────────────────────────────────────────────────────┘
    │
    ▼
Output  6/D MHz
```

**Key specifications:**

| Parameter | Value |
|---|---|
| Input sample rate | 9 MHz |
| Rate conversion | ×2 / ÷3 → 6 MHz (fractional 2/3) |
| Data word width | 32-bit signed  —  s16.15 fixed-point |
| FIR taps | 250 (Kaiser window, ≥ 81 dB stopband attenuation) |
| FIR passband / stopband | 2.8 MHz / 3.2 MHz |
| IIR notch frequencies | 2.4 MHz and 5 MHz |
| CIC order / max decimation | N = 4 / D = 1–16 (runtime configurable) |
| Clock domains | clk (fast path) + clk_1 (slow path) |

---

## 3. Signal Processing Design

### 3.1 System Architecture

The DFE operates across **two clock domains** separated by a Gray-code asynchronous FIFO:

- **clk domain** — handles the high-rate path: upsample, FIR filter, downsample
- **clk_1 domain** — handles the low-rate path: IIR notch filters, CIC decimator

A valid-signal handshake (`din_valid` / `dout_valid`) flows through every block so the downstream module only processes data when a real sample is present.

### 3.2 Block 1 — Upsampler

**File:** `Interpolation.sv`

Inserts `L − 1 = 1` zero sample between each real input sample to raise the sampling rate from 9 MHz to 18 MHz. A 1-bit counter (`zero_count`) drives the output valid signal for all `L` output cycles.

```
din_valid ──▶  [ real sample ]──▶ dout_valid (cycle 0)
               [ zero insert ]──▶ dout_valid (cycle 1)
               [ wait...     ]──▶ dout_valid = 0
```

- Upsampling factor `L` is a Verilog parameter (default 2)
- Zero-insertion is computationally free but creates spectral images at multiples of Fs — removed by the downstream FIR

### 3.3 Block 2 — FIR Anti-Alias Filter

**File:** `FIR.sv`

A 250-tap, fully-pipelined direct-form FIR lowpass filter. All 250 multiply-accumulate operations are pipelined in parallel to maximise clock frequency.

**Architecture:**

```
Stage 1 │ Shift register  — 250 samples of 32-bit delay line
Stage 2 │ Parallel multiply — 250 products computed in one cycle
Stage 3 │ Tree accumulation — pipeline of additions
Stage 4 │ Normalise — right-shift by COEFF_FRAC = 15 bits
```

**Internal widths** prevent overflow:

```
ACC_WIDTH = DATA_WIDTH + COEFF_WIDTH + ⌈log₂(TAPS)⌉
          = 32         + 32          + 8
          = 72 bits
```

**Coefficient loading:**

```verilog
initial $readmemh("coeffs.hex", h);   // 250 × 32-bit s16.15 words
```

The `valid_pipe[TAPS:0]` shift register propagates the enable flag through all 250 pipeline stages so `dout_valid` precisely tracks the latency.

| Parameter | Value |
|---|---|
| Taps | 250 |
| Window | Kaiser (`scipy.signal.kaiserord`) |
| Stopband attenuation | ≥ 81 dB |
| Passband edge fp | 2.8 MHz |
| Stopband edge fs | 3.2 MHz |
| Coefficient format | s16.15  (32-bit signed, ×2¹⁵) |
| Accumulator | 72-bit signed |

### 3.4 Block 3 — Downsampler

**File:** `Decimator.sv`

A modulo-M counter selects every Mth FIR output sample and discards the rest. Together with the upsampler this realises the exact **2/3 fractional rate**:

```
9 MHz  ×2  →  18 MHz  ÷3  →  6 MHz
```

The counter width is `$clog2(M)` bits, making the block fully parameterised.

### 3.5 Block 4 — Asynchronous FIFO

**File:** `FIFO.sv`

A dual-clock FIFO bridges the `clk → clk_1` clock domain crossing. Both the write pointer (`wr_ptr`) and read pointer (`rd_ptr`) are maintained in **Gray code** and synchronised across the domain boundary with 2-stage flip-flop chains to eliminate metastability.

```
clk domain (write)            clk_1 domain (read)
──────────────────            ───────────────────
wr_ptr_bin  → Gray            rd_ptr_bin  → Gray
wr_ptr_gray ──2FF──▶ sync     rd_ptr_gray ──2FF──▶ sync
                      │                            │
                      └────── empty detect ────────┘
```

| Parameter | Value |
|---|---|
| Depth | 2^ADDR_WIDTH = 16 entries |
| Width | 32 bits signed |
| Write clock | clk |
| Read clock | clk_1 |
| CDC mechanism | Gray-code + 2-FF synchroniser |

### 3.6 Block 5 — IIR Dual-Notch Filter Bank

**Files:** `IIR.sv`, `IIR_top.sv`

Two second-order IIR **resonator notch** filters are cascaded to suppress two interfering tones. Each stage implements the bilinear resonator structure:

```
y[n]  =  x[n]  +  z1[n]

z1[n] = 2R·cos(θ)·y[n] − 2·cos(θ)·x[n] + z2[n]
z2[n] = x[n] − R²·y[n]
```

All multiplications use **32×32 → 64-bit** intermediates. Results are truncated to S1.30 by taking bits `[62:31]` or `[63:32]`. State variables `z1` (37-bit) and `z2` (35-bit) carry extra guard bits to prevent saturation.

**Notch parameters:**

| Stage | Frequency | cos(θ) | S1.30 integer |
|---|---|---|---|
| 1 | 2.4 MHz | cos(2π × 2.4/6) = 0.5 | 536 870 912 |
| 2 | 5.0 MHz | cos(2π × 5/6) ≈ −0.866 | −868 675 383 |
| Both | — | R = 0.95 | 1 020 054 732 |

The pole radius `R` and angle `cos(θ)` are **elaboration-time parameters**, making the notch frequencies fully configurable without RTL changes.

### 3.7 Block 6 — CIC Decimator

**File:** `CIC.sv`

A 4th-order Cascaded Integrator-Comb filter with **runtime-programmable** decimation ratio `D` (1–16). Internal register width is automatically computed to prevent overflow for any valid D:

```
REGWIDTH = INPUTWIDTH + N × ⌈log₂(MAX_D)⌉
         = 32         + 4 × 4
         = 48 bits
```

**Architecture:**

```
Integrator section (full rate)          Comb section (÷D rate)
──────────────────────────────          ──────────────────────
d_in → Σ → Σ → Σ → Σ → [÷D] →         Δ → Δ → Δ → Δ → d_out
       d1   d2   d3   d4   count        d5   d6   d7   d8
```

The output is right-shifted by `N × log₂D` to compensate for CIC passband gain of `D^N`. The shift amount is computed by a combinational `case` statement on `D` to avoid synthesis issues with `$clog2` in runtime expressions.

### 3.8 Fixed-Point Arithmetic

All data paths use a consistent fixed-point convention:

| Signal / Coefficient | Format | Bits | Scale |
|---|---|---|---|
| Input / output samples | s16.15 | 32 | ×2¹⁵ = 32 768 |
| FIR coefficients | s16.15 | 32 | ×2¹⁵ — from coeffs.hex |
| FIR accumulator | extended | 72 | Prevents 250-tap overflow |
| IIR pole radius R, cos(θ) | S1.30 | 32 | ×2³⁰ |
| IIR multiplier intermediates | 64-bit | 64 | Truncated to [62:31] |
| IIR state z1 | extended | 37 | Guard bits vs. saturation |
| IIR state z2 | extended | 35 | Guard bits vs. saturation |

---

## 4. Python Verification

### 4.1 Verification Flow

The Python script (`Fractional_Decimation_.py`) is both the **golden reference model** and the **test-bench generator**. It models the entire chain at floating-point precision, quantises to fixed-point, generates RTL stimulus files, and compares the RTL simulation output back against the reference.

```
① Generate multi-tone signal  (9 MHz, 3 ms, 6 tones)
        ↓
② Design FIR  (kaiserord: 81 dB, Δf=400 kHz, 250 taps)
        ↓
③ Model chain  (upsample ×2  →  lfilter  →  downsample ×3)
        ↓
④ Quantise to s16.15  (round, clip to ±2³¹)
        ↓
⑤ Write files:  stimulus_input.txt  ·  coeffs.hex  ·  python_output.txt
        ↓
⑥ [Run RTL simulation → verilog_output.txt]
        ↓
⑦ Compare:  SNR  ·  max/RMS error  ·  cross-correlation  ·  FFT overlay
```

### 4.2 Test Signal

The test signal combines six sinusoids to exercise every part of the filter chain simultaneously:

| Tone | Frequency | Expected After DFE |
|---|---|---|
| f₁ | 400 kHz | ✅ Passed — in FIR passband |
| f₂ | 700 kHz | ✅ Passed — in FIR passband |
| f₃ | 1.0 MHz | ✅ Passed — in FIR passband |
| f₄ | 1.2 MHz | ✅ Passed — in FIR passband |
| f₅ | 2.4 MHz | ❌ Notched — IIR Stage 1 target |
| f₆ | 5.0 MHz | ❌ Notched — IIR Stage 2 target + FIR alias |

### 4.3 Filter Design

```python
from scipy.signal import firwin, kaiserord

fs_up  = 18e6          # Upsampled rate
fp     = 2.8e6         # Passband edge
fs_    = 3.2e6         # Stopband edge
att_db = 81.0          # Minimum stopband attenuation

nyq    = fs_up / 2.0
delta  = (fs_ - fp) / nyq
N, beta = kaiserord(att_db, delta)   # Determines taps and window shape
cutoff  = (fp + fs_) / 2.0
h = firwin(250, cutoff / nyq, window=('kaiser', beta))
```

Coefficients are then quantised to s16.15 and written to `coeffs.hex`:

```python
def float_to_s16_15(x):
    return np.clip(np.round(x * 32768.0), -2**31, 2**31-1).astype(np.int32)

with open("coeffs.hex", "w") as f:
    for v in h_s16_15:
        f.write("{:08x}\n".format(np.uint32(np.int32(v)).item()))
```

### 4.4 Numerical Accuracy Metrics

After RTL simulation, `compare_outputs()` computes:

| Metric | Description |
|---|---|
| **SNR** | `10·log₁₀(signal_power / error_power)` — DC removed, startup stripped |
| **Max absolute error** | `max │y_rtl[n] − y_python[n]│` |
| **RMS error** | `√(mean(error²))` |
| **Normalised cross-correlation** | `max(xcorr) / N` — confirms time alignment |
| **FFT overlay** | 8192-point FFT at both 9 MHz and 3 MHz rates |

### 4.5 Running the Verification

**Step 1 — Generate stimulus and coefficients:**

```bash
pip install numpy scipy matplotlib
python Fractional_Decimation_.py
# Writes: stimulus_input.txt  coeffs.hex  python_output.txt
```

**Step 2 — Run RTL simulation:**

```bash
# With your simulator of choice (e.g. Icarus Verilog):
iverilog -o dfe_sim FIR_IIR.sv tb_FIR_IIR.sv
vvp dfe_sim
# Writes: verilog_output.txt
```

**Step 3 — Compare:**

```bash
# Run compare_outputs() inside the script:
python Fractional_Decimation_.py
# Prints SNR, max error, RMS error, correlation; opens waveform + FFT plots
```

---

## 5. ASIC Implementation — NanGate 45nm (Synopsys ICC)

### 5.1 Synthesis Results

**Tool:** Synopsys Design Compiler G-2012.06-SP2  
**Library:** NangateOpenCellLibrary_ss0p95vn40c (slow-slow, 0.95 V, −40 °C)

| Metric | Value |
|---|---|
| Total cell area | 139 881 library units |
| Leaf cells | 47 566 |
| Sequential cells | 13 588 |
| Combinational cells | 33 978 |
| Buf / Inv cells | 4 619 |

**Block-level area breakdown:**

| Block | Module | Area | % |
|---|---|---|---|
| Fractional Decimator | `Fractional_decimetor` | 118 815 | **84.9%** |
| IIR Dual Notch | `IIR_top` | 8 953 | 6.4% |
| CIC Decimator | `CIC` | 7 324 | 5.2% |
| Async FIFO | `fifo` | 4 789 | 3.4% |
| **TOTAL** | `FIR_IIR` | **139 881** | 100% |

The FIR filter dominates area (≈85% of the fractional decimator) due to 250 parallel product registers and a deep tree accumulation.

**Post-synthesis timing:**

| Domain | Period | Critical Path | Setup Slack | Hold Violations |
|---|---|---|---|---|
| clk | 6.00 ns (166 MHz) | 4.90 ns | +0.72 ns ✅ | 12 668 (pre-CTS) |
| clk_1 | 18.00 ns (55 MHz) | 7.68 ns | +9.93 ns ✅ | 909 (pre-CTS) |

> The pre-CTS hold violations are expected and are fully resolved by CTS buffer insertion during place-and-route.

### 5.2 Place-and-Route

**Tool:** Synopsys IC Compiler G-2012.06-ICC-SP2  
**Parasitic extraction:** StarRC / StarXtract — RealRC mode, MIN_MAX model, −40/−40/−40 derate  
**SI analysis:** Delta-delay computation + static-noise analysis enabled. Crosstalk prevention threshold: 0.35×VDD

The clock tree was synthesised to resolve all pre-CTS hold violations. Post-CTS buffer insertion dominates the increase in cell count from synthesis to PnR:

| Metric | Post-Synthesis | Post-Route |
|---|---|---|
| Total cell area | 139 881 | 991 219 |
| Leaf cells | 47 566 | 739 421 |
| Buf / Inv cells | 4 619 | **596 421** (CTS) |
| Sequential cells | 13 588 | 45 824 |
| Net wire length | — | 6 774 203 units |

### 5.3 Timing Sign-Off

Post-route timing was verified at the worst-case SS 0.95 V −40 °C corner with full LPE parasitics:

| Metric | clk (166 MHz) |
|---|---|
| Critical path | 4.60 ns |
| Setup slack | **+1.04 ns ✅** |
| Logic levels | 112 |
| Total negative slack | **0.00 ns ✅** |
| Hold violations | **0 ✅** (resolved by CTS) |
| Nets with DRC violations | **0 ✅** |
| Max Trans / Max Cap | **0 / 0 ✅** |

### 5.4 Physical Verification

| Check | Tool | Result |
|---|---|---|
| DRC | Synopsys ICC | 0 violations ✅ |
| LVS | Synopsys ICC Netgen | PASSED — 0 short / 0 open / 0 electrical errors ✅ |
| Antenna | — | 0 violations ✅ |
| Via optimisation | Synopsys ICC | 97.15% double-via rate (3.25M / 3.34M vias) ✅ |

LVS confirmed zero errors across all 16 metal layers:

```
Total SHORT Nets:                    0
Total OPEN Nets:                     0
Total Electrical Equivalent Errors:  0
Total Must-Joint Errors:             0
```

### 5.5 IR Drop & Noise

**IR drop — VDD / VSS (target: 22 mV):**

| Net | IR Drop | Status |
|---|---|---|
| VDD | 12.45 mV | ✅ well within 22 mV target |
| VSS | 12.75 mV | ✅ well within 22 mV target |

Power grid: metal9/10 rings (1.6 µm wide) + 30 straps per layer (0.8 µm average).  
Routing track usage: VDD 21% on metal10, 20% on metal9.

**Static noise analysis:**

All pins passed the ±0.35×VDD (0.33 V) noise threshold. The only pins at zero slack are exactly on the boundary — no failures.

---

## 6. ASIC Implementation — Sky130 130nm (OpenROAD)

### 6.1 OpenLane Configuration

The identical RTL was re-targeted to the SkyWater Sky130 130nm open-source PDK with the following key settings:

```json
{
  "DESIGN_NAME":     "TOP",
  "CLOCK_PORT":      "clk",
  "CLOCK_PERIOD":    "14.0",
  "SYNTH_STRATEGY":  "AREA 3",
  "FP_CORE_UTIL":    20
}
```

Pin placement (`pin_order.cfg`):

| Edge | Pins | Min pitch |
|---|---|---|
| North | `data_in[*]`, `D[*]`, `rst_n` | 0.5 µm |
| South | `data_out[*]` | 0.5 µm |
| East | `clk` | 0.9 µm |
| West | `clk_1` | 0.3 µm |

**OpenLane flow stages:**

```
Synthesis (Yosys)  →  Floorplan (init_fp)  →  Placement (OpenDP)
    →  CTS (TritonCTS)  →  Global Route (FastRoute)
    →  Detailed Route (TritonRoute)  →  DRC (Magic)  →  LVS (Netgen)  →  GDSII
```

### 6.2 Timing Sign-Off

**Tool:** OpenROAD STA  
**Target clock:** 14.0 ns (71.4 MHz)  
**SDC:** Asynchronous clock groups with explicit false paths between clk and clk_1 (CDC handled by FIFO)

| Metric | Post-GRT | Post-Route (Final) |
|---|---|---|
| Worst slack — Setup | 3.79 ns ✅ | **4.09 ns ✅** |
| Worst slack — Hold | 0.01 ns ✅ | **0.08 ns ✅** |
| Total negative slack (TNS) | 0.00 ✅ | **0.00 ✅** |
| Violating paths | 0 | **0 ✅** |
| Clock skew — clk | 0.24 ns | 0.24 ns |
| Clock skew — clk_1 | 0.26 ns | 0.26 ns |

Clock uncertainty was set conservatively for Sky130:
```tcl
set_clock_uncertainty 0.4  [get_clocks clk]
set_clock_uncertainty 0.7  [get_clocks clk_1]
```

### 6.3 Power Analysis

**Corner:** Typical  
**Tool:** OpenROAD report_power

| Group | Internal | Switching | Leakage | Total | % |
|---|---|---|---|---|---|
| Sequential | 56.4 mW | 2.5 mW | < 1 µW | 58.9 mW | 9.3% |
| **Combinational** | **316 mW** | **258 mW** | ~4 µW | **574 mW** | **90.7%** |
| **TOTAL** | 373 mW | 260 mW | 4.09 µW | **633 mW** | 100% |

Combinational logic dominates at 90.7%, driven by the 250-tap FIR MAC tree.  
Switching power (41% of total) reflects high toggle activity in the shift-register delay line.

**Design area:**

| Metric | Value |
|---|---|
| Design area | 5 046 736 µm² (5.05 mm²) |
| Core utilisation | 20% |
| Estimated die size | ~2.25 mm × 2.25 mm |
| Total cells | 702 816 |
| Flip-flops | 18 593 (2.6%) |
| Combinational cells | 684 223 (97.4%) |
| Technology | SkyWater Sky130  130nm |

### 6.4 Physical Verification

| Check | Tool | Result |
|---|---|---|
| DRC | Magic VLSI | **No DRC violations after GDS streaming out ✅** |
| LVS | Netgen | **PASSED — 0 errors ✅** |
| Antenna violations | OpenLane antenna check | **0 ✅** |

```
[INFO]: Running Magic DRC (log: .../signoff/4-drc.log)...
[INFO]: Converting Magic DRC database to various tool-readable formats...
[INFO]: No DRC violations after GDS streaming out.
```

---

## 7. Technology Comparison

| Metric | NanGate 45nm (ICC) | Sky130 130nm (OpenROAD) |
|---|---|---|
| **Target frequency** | 166 MHz | 71.4 MHz |
| **Setup slack (worst)** | +1.04 ns ✅ | +4.09 ns ✅ |
| **Hold slack (worst)** | 0.00 ns ✅ | +0.08 ns ✅ |
| **TNS** | 0.00 ✅ | 0.00 ✅ |
| **Clock skew — clk** | < 0.27 ns | 0.24 ns |
| **DRC violations** | 0 ✅ | 0 ✅ |
| **LVS** | PASS ✅ | PASS ✅ |
| **Die area** | ~0.30 mm² | ~5.05 mm² |
| **Area ratio** | 1× | **16.8× larger** |
| **Core utilisation** | ~80–90% | 20% |
| **Total power** | Not reported | 633 mW (typical) |
| **IR drop VDD/VSS** | 12.45 / 12.75 mV ✅ | Not reported |
| **Voltage** | 1.1 V | 1.8 V |
| **Toolchain** | Synopsys DC + ICC (commercial) | Yosys + OpenROAD (free/open) |
| **PDK access** | Commercial license | Open-source (SKY130) |

**Area scaling explanation:**

```
Geometric scaling:  (130 / 45)² = 8.35×
Actual ratio:       16.8×
─────────────────────────────────────────
Difference (~2×) explained by:
  • Sky130 run at 20% utilisation (vs ~85% NanGate)
  • Different CTS strategy (less aggressive hold fixing)
  • 130nm standard cells have larger minimum feature size
```

---

## 8. Key Results Summary

```
╔══════════════════════════════════════════════════════════════════════╗
║                    DFE — SIGN-OFF SUMMARY                           ║
╠══════════════════════════════╦══════════════════════════════════════╣
║  Design                      ║  Fractional DEC + IIR Notch + CIC   ║
║  RTL Language                ║  SystemVerilog  (7 modules)          ║
║  Verification                ║  Python golden model  →  SNR / xcorr ║
╠══════════════════════════════╬══════════════════════════════════════╣
║  NanGate 45nm  (ICC)         ║                                      ║
║    Max frequency             ║  166 MHz                             ║
║    Setup slack               ║  +1.04 ns  ✅                        ║
║    Hold violations           ║  0  (CTS-resolved)  ✅               ║
║    DRC / LVS                 ║  PASS  ✅                            ║
║    IR drop  VDD / VSS        ║  12.45 / 12.75 mV  (target 22 mV) ✅║
║    Total cell area           ║  991 219 lib units  (~0.30 mm²)      ║
╠══════════════════════════════╬══════════════════════════════════════╣
║  Sky130 130nm  (OpenROAD)    ║                                      ║
║    Max frequency             ║  71.4 MHz                            ║
║    Setup slack               ║  +4.09 ns  ✅                        ║
║    Hold slack                ║  +0.08 ns  ✅                        ║
║    DRC / LVS                 ║  PASS  ✅                            ║
║    Total power               ║  633 mW  (90.7% combinational)       ║
║    Design area               ║  5 046 736 µm²  (5.05 mm²  @ 20%)   ║
╚══════════════════════════════╩══════════════════════════════════════╝
```
