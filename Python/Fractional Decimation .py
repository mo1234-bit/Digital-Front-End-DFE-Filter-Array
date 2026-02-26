import numpy as np
from scipy.signal import firwin, kaiserord, lfilter, freqz, group_delay
import matplotlib.pyplot as plt
import os
from numpy.fft import fft, fftshift

def my_upsample(x, L):
    y = np.zeros(len(x) * L, dtype=float)
    y[::L] = x
    return y

def my_downsample(y, M):
    return y[::M]

def design_fir_kaiser(numtaps, fs_in=9e6, L=2):
    fs_up = fs_in * L
    fp = 2.8e6
    fs = 3.2e6
    att_db = 81.0
    nyq = fs_up / 2.0
    delta_f = (fs - fp) / nyq
    nt, beta = kaiserord(att_db, delta_f)
    cutoff = (fp + fs) / 2.0
    h = firwin(numtaps, cutoff / nyq, window=('kaiser', beta))
    return h, fs_up

def plot_freq_response(h, fs):
    # Compute frequency response
    w, H = freqz(h, worN=8192, fs=fs)
    gd_w, gd = group_delay((h, 1.0), fs=fs)

    plt.figure(figsize=(12, 8))

    # Magnitude response
    plt.subplot(3, 1, 1)
    plt.plot(w / 1e6, 20 * np.log10(np.abs(H)), linewidth=1.0)
    plt.title("FIR Filter Frequency Response")
    plt.ylabel("Magnitude (dB)")
    plt.grid(True, alpha=0.3)
    plt.axvline(2.8, color='g', linestyle='--', label='Passband edge')
    plt.axvline(3.2, color='r', linestyle='--', label='Stopband edge')
    plt.legend()

    # Phase response
    plt.subplot(3, 1, 2)
    plt.plot(w / 1e6, np.unwrap(np.angle(H)), linewidth=1.0)
    plt.ylabel("Phase (radians)")
    plt.grid(True, alpha=0.3)

    # Group delay
    plt.subplot(3, 1, 3)
    plt.plot(gd_w / 1e6, gd, linewidth=1.0)
    plt.xlabel("Frequency (MHz)")
    plt.ylabel("Group Delay (samples)")
    plt.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.show()

def float_to_s16_15(x):
    SCALE = 32768.0  # 2^15
    x_scaled = np.round(x * SCALE)
    x_clipped = np.clip(x_scaled, -2147483648, 2147483647)
    return x_clipped.astype(np.int32)

def s16_15_to_float(x):
    SCALE = 32768.0
    return x.astype(np.float64) / SCALE

def s16_15_to_hex_str(arr):
    out = []
    for v in arr:
        u = np.uint32(np.int32(v)).item()
        out.append("{:08x}".format(u))
    return out
from DSP_functions import (
    generate_signal,
    plot_signal_and_spectrum,
    compare_input_output_spectrum,
    FixedPointArray,
)
def generate_files():
    fs_in = 9e6
    stop_time = 3e-3
    freqs = [0.4e6, 1e6, 1.2e6, 0.7e6, 2.4e6, 5e6]
    t, x = generate_signal(freqs, fs_in, stop_time)
    h, fs_up = design_fir_kaiser(numtaps=250, fs_in=fs_in, L=2)

    # Plot frequency response
    plot_freq_response(h, fs_up)

    x_up = my_upsample(x, 2)
    y_filt = lfilter(h, [1.0], x_up)
    y = my_downsample(y_filt, 3)

    x_s16_15 = float_to_s16_15(x)
    h_s16_15 = float_to_s16_15(h)
    y_s16_15 = float_to_s16_15(y)
    
    x_float = s16_15_to_float(x_s16_15)
    h_float = s16_15_to_float(h_s16_15)
    y_float = s16_15_to_float(y_s16_15)

    x_fixed = FixedPointArray(x, word_length=32, frac_bits=15)
    x_fixed_raw = x_fixed.quantize(32, 15).raw_values  # integer values for RTL
    np.savetxt("stimulus_input.txt", x_fixed_raw, fmt="%d")
    np.savetxt("python_output.txt", y_s16_15, fmt="%.32f")

    hex_lines = s16_15_to_hex_str(h_s16_15)
    with open("coeffs.hex", "w") as f:
        for line in hex_lines:
            f.write(line + "\n")

def compare_outputs():
    if not os.path.exists("verilog_output.txt"):
        print("\nverilog_output.txt not found — run Verilog sim first.")
        return

    x_in = np.loadtxt("stimulus_input.txt")
    y_py = np.loadtxt("python_output.txt")
    y_ver = np.loadtxt("verilog_output.txt")
    w=float_to_s16_15(y_ver)
    np.savetxt("verilog_fixed.txt", w)
    if os.path.exists("verilogIIR_output.txt"):
        rtl_output = np.loadtxt("verilogIIR_output.txt", converters={0: lambda x: int(float(x))})
        IIR = (FixedPointArray(rtl_output, word_length=32, frac_bits=15).values) / (2**15)
        #IIR= float_to_s16_15(IIR_f)
    else:
        IIR = None

    n = min(len(y_py), len(y_ver))
    # Delay Python output by 1 sample to match RTL latenc
    y_py = -y_py[500:n]/ (2**15)
    y_ver = y_ver[500:n]/ (2**15)
    error = y_ver - y_py
    max_error = np.max(np.abs(error))
    rms_error = np.sqrt(np.mean(error**2))
    # Convert to float
    y_ref = y_py 
    y_rtl = y_ver 

# Remove startup
    N0 = 100
    y_ref = y_ref[N0:]
    y_rtl = y_rtl[N0:]

# Remove DC
    y_ref -= np.mean(y_ref)
    y_rtl -= np.mean(y_rtl)

# Error
    err = y_rtl - y_ref
    err -= np.mean(err)


    signal_power = np.mean(y_ref**2)
    error_power  = np.mean(err**2)

    snr_db = 10 * np.log10(signal_power / error_power)
    print(f"SNR = {snr_db:.2f} dB")


    print("\n" + "=" * 60)
    print("COMPARISON RESULTS")
    print("=" * 60)
    print(f"Python outputs:  {len(y_py)}")
    print(f"Verilog outputs: {len(y_ver)}")
    print(f"Max error:       {max_error:.10f}")
    print(f"RMS error:       {rms_error:.10f}")
    print("=" * 60)

    plt.figure(figsize=(12, 8))
    y_py_n = y_py / np.sqrt(np.mean(y_py**2))
    y_ver_n = y_ver / np.sqrt(np.mean(y_ver**2))

    if IIR is not None:
        IIR_n = IIR / np.sqrt(np.mean(IIR**2))
        corr_IRR = np.correlate(y_ver_n, IIR_n, mode="full")
        print(f"Max normalized correlation with IIR = {corr_IRR.max()/len(y_ver_n):.4f}")

    corr = np.correlate(y_py_n, y_ver_n, mode="full")
    print(f"Max normalized correlation = {corr.max()/len(y_py_n):.4f}")

    plt.subplot(4, 1, 1)
    plt.plot(x_in[100:130], linewidth=0.8)
    plt.title("Input Signal (s16.15 format)")
    plt.ylabel("Amplitude")
    plt.grid(True, alpha=0.3)

    plt.subplot(4, 1, 2)
    plt.plot(y_py[:3000], label="Python Reference", linewidth=0.8)
    plt.title("Python Reference Output")
    plt.ylabel("Amplitude")
    plt.legend()
    plt.grid(True, alpha=0.3)

    plt.subplot(4, 1, 3)
    plt.plot(y_ver[100:600], label="Verilog Output", color='orange', linewidth=0.8)
    plt.title("Verilog Output")
    plt.ylabel("Amplitude")
    plt.legend()
    plt.grid(True, alpha=0.3)

    plt.subplot(4, 1, 4)
    plt.plot(y_ver[100:300], label="Verilog Output", linestyle='--', color='red', linewidth=0.8)
    plt.plot(y_py[100:300], label="Python Reference", linestyle='solid', color='black', linewidth=0.8)
    plt.title("Comparison: Python vs Verilog")
    plt.ylabel("Amplitude")
    plt.legend()
    plt.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.show()
    stop_time = 3e-3
    fft_len=8192
    freqs = [0.4e6, 1e6, 1.2e6, 0.7e6, 2.4e6, 5e6]
    fig_float, axes_float = plot_signal_and_spectrum(IIR[:500], 3e6, freqs, fft_len=fft_len, stop_time=stop_time)
    axes_float[0].set_title("Python Output - Floating Input (Time Domain)")
    axes_float[1].set_title("Python Output - Floating Input (Frequency Domain)")


    # RTL output (if available)

    fig_rtl, axes_rtl = plot_signal_and_spectrum(IIR[100:600], 3e6, freqs, fft_len=fft_len, stop_time=stop_time)
    axes_rtl[0].set_title("RTL Output - Time Domain")
    axes_rtl[1].set_title("RTL Output - Frequency Domain")

        # Compare floating input vs Python floating output
    fig_cmp1 = compare_input_output_spectrum(x_in[:500], IIR[100:600], 9e6, 3e6, freqs, fft_len, title="INPUT SIGNAL (Floating) vs PYTHON OUTPUT (Floating)")

        # Compare Python output vs RTL output
    fig_cmp3 = compare_input_output_spectrum(IIR[100:600], IIR[100:600], 3e6, 3e6, freqs, fft_len, title="PYTHON OUTPUT(fixed-point) vs RTL OUTPUT")
    N_plot = 500    
        # Overlay time-domain (first N_plot samples)
    plt.figure(figsize=(10, 5))
    plt.plot(y_py[:N_plot], label="Python Output (Floating Input)")
    plt.plot(y_ver[:N_plot], label="RTL Output", alpha=0.5)
    plt.xlabel("Sample Index")
    plt.ylabel("Amplitude")
    plt.title(f"Python & RTL Outputs Comparison (first {N_plot} samples)")
    plt.legend()
    plt.grid(True)
    plt.show()


if __name__ == "__main__":
    generate_files()
    compare_outputs()
