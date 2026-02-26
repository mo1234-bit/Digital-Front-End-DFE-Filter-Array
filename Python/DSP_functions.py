import numpy as np
import matplotlib.pyplot as plt
from numpy.fft import fft, fftshift
from math import pi

def generate_signal(frequencies, fs, stop_time=3):
    """
    Generate a time-domain signal from given frequencies.

    Parameters:
    -----------
    frequencies : list
        List of frequency components in Hz
    fs : float
        Sampling frequency in Hz
    stop_time : float
        Duration of the signal in seconds (default: 3)

    Returns:
    --------
    t : ndarray
        Time array
    x_n : ndarray
        Time-domain signal
    """
    # Generate time array
    t = np.arange(0, stop_time, 1 / fs)

    # Generate signal as sum of sinusoids
    x_n = np.sum([np.sin(2 * pi * f * t) for f in frequencies], axis=0)

    return t, x_n


def plot_signal_and_spectrum(x_n, fs, frequencies, fft_len=1024, stop_time=3):
    """
    Compute FFT and plot time-domain signal and frequency spectrum with aliasing annotations.
    Automatically categorizes frequencies into zones based on sampling frequency.

    Zones:
    - Zone 1: 0 to fs/2 (Nyquist) - No aliasing
    - Zone 2: fs/2 to fs - First aliasing zone
    - Zone 3: > fs - Higher aliasing zones

    Parameters:
    -----------
    x_n : ndarray
        Time-domain signal
    fs : float
        Sampling frequency
    frequencies : list
        List of all frequency components in Hz
    fft_len : int
        Length of FFT (default: 1024)
    stop_time : float
        Duration of the signal in seconds (default: 3, used for time axis)

    Returns:
    --------
    fig, axes : matplotlib figure and axes objects
    """
    # Reconstruct time array from signal length and fs
    t = np.arange(0, stop_time, 1 / fs)

    # Categorize frequencies into zones based on Nyquist frequency
    nyquist = fs / 2
    zone1_freqs = [f for f in frequencies if 0 <= f <= nyquist]
    zone2_freqs = [f for f in frequencies if nyquist < f <= fs]
    zone3_freqs = [f for f in frequencies if f > fs]

    # Determine which zones to show based on presence of frequencies
    show_zone2 = len(zone2_freqs) > 0
    show_zone3 = len(zone3_freqs) > 0

    # Compute FFT spectrum (shifted and normalized)
    X_k = fftshift(np.abs(fft(x_n, fft_len)) / (len(x_n) / 2))

    # Frequency array
    freq = np.linspace(-fs / 2, fs / 2, fft_len)

    # Create plots
    fig, axes = plt.subplots(2, 1, figsize=(14, 8))

    # Plot time-domain signal
    axes[0].plot(t, x_n)
    axes[0].set_xlabel("Time (s)")
    axes[0].set_ylabel("Amplitude")
    axes[0].set_title(f"Input Signal with Frequencies: {frequencies} Hz")
    axes[0].grid(True, alpha=0.3)

    # Plot frequency spectrum
    axes[1].plot(freq, np.real(X_k))
    axes[1].set_xlabel("FFT Frequency (Hz)")
    axes[1].set_ylabel("Amplitude")
    axes[1].set_title("FFT Spectrum with Aliased Frequencies")
    axes[1].set_ylim(0, 1.1)
    axes[1].grid(True, alpha=0.3)

    # Zone 1 true frequencies (solid green lines)
    for i, fx in enumerate(zone1_freqs):
        axes[1].axvline(fx, color='green', linestyle='-',
                       label='Zone 1 True Freq' if i == 0 else None)

    # Zone 2 true and aliased frequencies (if present)
    if show_zone2:
        for i, fx in enumerate(zone2_freqs):
            aliased = abs(((fx + fs/2) % fs) - fs/2)
            axes[1].axvline(fx, color='orange', linestyle='--',
                           label='Zone 2 True Freq' if i == 0 else None)
            axes[1].axvline(aliased, color='red', linestyle=':',
                           label='Zone 2 Aliased Freq' if i == 0 else None)

    # Zone 3 true and aliased frequencies (if present)
    if show_zone3:
        for i, fx in enumerate(zone3_freqs):
            aliased = abs(((fx + fs/2) % fs) - fs/2)
            axes[1].axvline(fx, color='purple', linestyle='--',
                           label='Zone 3 True Freq' if i == 0 else None)
            axes[1].axvline(aliased, color='pink', linestyle=':',
                           label='Zone 3 Aliased Freq' if i == 0 else None)

    # Nyquist boundaries
    axes[1].axvline(fs/2, color='k', linestyle='--', label='Nyquist +fs/2')
    axes[1].axvline(-fs/2, color='k', linestyle='--', label='Nyquist -fs/2')

    axes[1].legend()
    plt.tight_layout()

    return fig, axes


# ========== MAIN EXECUTION ==========
if __name__ == "__main__":
    # Parameters
    fs = 9
    fft_len = 1024
    stop_time = 3

    # All frequencies (mix of different zones)
    # all_freqs = [3, 2, 1, 0.8]  # Zone 1 only
    # all_freqs = [3, 2, 1, 0.8, 5]  # Zone 1 + Zone 2
    all_freqs = [3, 2, 1]  # All zones

    # Generate signal
    t, x_n = generate_signal(all_freqs, fs, stop_time)

    # Plot with automatic zone detection (only needs x_n, not t)
    fig, axes = plot_signal_and_spectrum(x_n, fs, all_freqs, fft_len, stop_time)
    plt.show()

"""
Fixed-Point Arithmetic Utilities

This module provides classes and functions for fixed-point arithmetic
operations using Q-format representation.

Primary format for DFE system: s16.15 (16-bit signed, 15 fractional bits)
- Range: [-1.0, +0.999969]
- Resolution: 2^-15 = 3.05e-5

Also supports arbitrary Q-formats for coefficients and internal calculations.
"""

import numpy as np
from typing import Union, Tuple


class FixedPoint:
    """
    Fixed-point number representation and arithmetic.

    Supports signed and unsigned Q-format fixed-point numbers with
    configurable word length and fractional bits.

    Q-format notation: Qm.n or sQm.n
    - s: signed (optional prefix)
    - m: number of integer bits
    - n: number of fractional bits
    - Total bits: m + n (+ 1 for sign bit if signed)

    Examples:
    - s16.15: 16 total bits, 15 fractional, 1 sign + 0 integer
    - s32.31: 32 total bits, 31 fractional, 1 sign + 0 integer
    - Q17: 18 bits, 17 fractional, 1 integer (unsigned)
    """

    def __init__(self,
                 value: Union[float, int] = 0.0,
                 word_length: int = 16,
                 frac_bits: int = 15,
                 signed: bool = True,
                 raw: bool = False):
        """
        Initialize a fixed-point number.

        Args:
            value: Value to convert (float or int)
            word_length: Total number of bits
            frac_bits: Number of fractional bits
            signed: True for signed, False for unsigned
            raw: If True, treat value as raw integer representation
        """
        self.word_length = word_length
        self.frac_bits = frac_bits
        self.signed = signed
        self.int_bits = word_length - frac_bits - (1 if signed else 0)

        if raw:
            # Value is already in integer representation
            self.raw_value = int(value)
        else:
            # Convert floating-point to fixed-point
            self.raw_value = self._float_to_fixed(value)

        # Apply saturation
        self.raw_value = self._saturate(self.raw_value)

    def _float_to_fixed(self, value: float) -> int:
        """
        Convert floating-point value to fixed-point integer representation.

        Args:
            value: Floating-point value

        Returns:
            int: Fixed-point integer representation
        """
        # Scale by 2^frac_bits and round
        scaled = value * (2 ** self.frac_bits)
        return int(np.round(scaled))

    def _fixed_to_float(self, raw: int) -> float:
        """
        Convert fixed-point integer representation to floating-point.

        Args:
            raw: Fixed-point integer representation

        Returns:
            float: Floating-point value
        """
        # Handle sign extension for signed numbers
        if self.signed:
            # Sign extend if necessary
            sign_bit = 1 << (self.word_length - 1)
            if raw & sign_bit:
                # Negative number - extend sign
                mask = (1 << self.word_length) - 1
                raw = raw | ~mask

        return raw / (2 ** self.frac_bits)

    def _saturate(self, value: int) -> int:
        """
        Saturate value to fit within word length.

        Args:
            value: Integer value to saturate

        Returns:
            int: Saturated value
        """
        if self.signed:
            max_val = (1 << (self.word_length - 1)) - 1
            min_val = -(1 << (self.word_length - 1))
        else:
            max_val = (1 << self.word_length) - 1
            min_val = 0

        if value > max_val:
            return max_val
        elif value < min_val:
            return min_val
        else:
            return value

    def _mask_bits(self, value: int) -> int:
        """
        Mask value to word length (wrap around).

        Args:
            value: Integer value

        Returns:
            int: Masked value
        """
        mask = (1 << self.word_length) - 1
        return value & mask

    @property
    def value(self) -> float:
        """Get the floating-point value."""
        return self._fixed_to_float(self.raw_value)

    @property
    def min_value(self) -> float:
        """Get the minimum representable value."""
        if self.signed:
            return -(2 ** self.int_bits)
        else:
            return 0.0

    @property
    def max_value(self) -> float:
        """Get the maximum representable value."""
        if self.signed:
            return (2 ** self.int_bits) - (2 ** -self.frac_bits)
        else:
            return (2 ** (self.int_bits + 1)) - (2 ** -self.frac_bits)

    @property
    def resolution(self) -> float:
        """Get the resolution (LSB value)."""
        return 2 ** -self.frac_bits

    def __add__(self, other: 'FixedPoint') -> 'FixedPoint':
        """Add two fixed-point numbers."""
        if self.frac_bits != other.frac_bits:
            # Align fractional bits
            if self.frac_bits > other.frac_bits:
                other_raw = other.raw_value << (self.frac_bits - other.frac_bits)
                result_frac = self.frac_bits
            else:
                self_raw = self.raw_value << (other.frac_bits - self.frac_bits)
                other_raw = other.raw_value
                result_frac = other.frac_bits
                return FixedPoint(self_raw + other_raw,
                                self.word_length, result_frac,
                                self.signed, raw=True)

        result_raw = self.raw_value + other.raw_value
        result_word_length = max(self.word_length, other.word_length) + 1

        return FixedPoint(result_raw, result_word_length, self.frac_bits,
                         self.signed, raw=True)

    def __sub__(self, other: 'FixedPoint') -> 'FixedPoint':
        """Subtract two fixed-point numbers."""
        if self.frac_bits != other.frac_bits:
            # Align fractional bits
            if self.frac_bits > other.frac_bits:
                other_raw = other.raw_value << (self.frac_bits - other.frac_bits)
                result_frac = self.frac_bits
            else:
                self_raw = self.raw_value << (other.frac_bits - self.frac_bits)
                other_raw = other.raw_value
                result_frac = other.frac_bits
                return FixedPoint(self_raw - other_raw,
                                self.word_length, result_frac,
                                self.signed, raw=True)

        result_raw = self.raw_value - other.raw_value
        result_word_length = max(self.word_length, other.word_length) + 1

        return FixedPoint(result_raw, result_word_length, self.frac_bits,
                         self.signed, raw=True)

    def __mul__(self, other: 'FixedPoint') -> 'FixedPoint':
        """Multiply two fixed-point numbers."""
        result_raw = self.raw_value * other.raw_value
        result_word_length = self.word_length + other.word_length
        result_frac_bits = self.frac_bits + other.frac_bits

        return FixedPoint(result_raw, result_word_length, result_frac_bits,
                         self.signed and other.signed, raw=True)

    def __repr__(self) -> str:
        """String representation."""
        sign_str = 's' if self.signed else 'u'
        return (f"FixedPoint({self.value:.10f}, "
                f"{sign_str}Q{self.int_bits}.{self.frac_bits}, "
                f"raw=0x{self.raw_value:0{self.word_length//4}X})")

    def __str__(self) -> str:
        """Simple string representation."""
        return f"{self.value:.10f}"

    def quantize(self, new_word_length: int, new_frac_bits: int,
                rounding: str = 'convergent') -> 'FixedPoint':
        """
        Quantize to a different fixed-point format.

        Args:
            new_word_length: New word length
            new_frac_bits: New number of fractional bits
            rounding: Rounding mode ('convergent', 'round', 'truncate')

        Returns:
            FixedPoint: Quantized value
        """
        # Calculate bit shift
        shift = self.frac_bits - new_frac_bits

        if shift > 0:
            # Reduce fractional bits (shift right with rounding)
            if rounding == 'truncate':
                new_raw = self.raw_value >> shift
            elif rounding == 'round':
                # Round half up
                new_raw = (self.raw_value + (1 << (shift - 1))) >> shift
            elif rounding == 'convergent':
                # Convergent rounding (round half to even)
                new_raw = convergent_round(self.raw_value, shift)
            else:
                raise ValueError(f"Unknown rounding mode: {rounding}")
        elif shift < 0:
            # Increase fractional bits (shift left)
            new_raw = self.raw_value << (-shift)
        else:
            new_raw = self.raw_value

        return FixedPoint(new_raw, new_word_length, new_frac_bits,
                         self.signed, raw=True)


def convergent_round(value: int, shift: int) -> int:
    """
    Perform convergent rounding (round half to even).

    This rounding mode rounds to the nearest even number when exactly
    halfway between two representable values, eliminating statistical bias.

    Args:
        value: Integer value to round
        shift: Number of bits to shift (must be > 0)

    Returns:
        int: Rounded value after right shift
    """
    if shift <= 0:
        return value

    # Get the bits that will be shifted out
    half = 1 << (shift - 1)
    mask = (1 << shift) - 1
    remainder = value & mask

    # Shifted value without rounding
    shifted = value >> shift

    if remainder < half:
        # Round down
        return shifted
    elif remainder > half:
        # Round up
        return shifted + 1
    else:
        # Exactly half - round to even
        if shifted & 1:
            # Odd - round up to make even
            return shifted + 1
        else:
            # Even - keep as is
            return shifted


class FixedPointArray:
    """
    Fixed-point array for efficient processing of signal arrays.

    This class provides vectorized fixed-point operations for
    processing arrays of samples.
    """

    def __init__(self,
                 values: np.ndarray,
                 word_length: int = 16,
                 frac_bits: int = 15,
                 signed: bool = True):
        """
        Initialize fixed-point array.

        Args:
            values: Array of floating-point values or raw integers
            word_length: Total number of bits
            frac_bits: Number of fractional bits
            signed: True for signed, False for unsigned
        """
        self.word_length = word_length
        self.frac_bits = frac_bits
        self.signed = signed
        self.int_bits = word_length - frac_bits - (1 if signed else 0)

        # Convert to fixed-point
        if values.dtype in [np.int32, np.int64]:
            self.raw_values = values.astype(np.int64)
        else:
            self.raw_values = self._float_to_fixed(values)

        # Apply saturation
        self.raw_values = self._saturate(self.raw_values)

    def _float_to_fixed(self, values: np.ndarray) -> np.ndarray:
        """Convert floating-point array to fixed-point."""
        scaled = values * (2 ** self.frac_bits)
        return np.round(scaled).astype(np.int64)

    def _fixed_to_float(self, raw: np.ndarray) -> np.ndarray:
        """Convert fixed-point array to floating-point."""
        return raw.astype(np.float64) / (2 ** self.frac_bits)

    def _saturate(self, values: np.ndarray) -> np.ndarray:
        """Saturate array values to fit within word length."""
        if self.signed:
            max_val = (1 << (self.word_length - 1)) - 1
            min_val = -(1 << (self.word_length - 1))
        else:
            max_val = (1 << self.word_length) - 1
            min_val = 0

        return np.clip(values, min_val, max_val)

    @property
    def values(self) -> np.ndarray:
        """Get floating-point representation of the array."""
        return self._fixed_to_float(self.raw_values)

    @property
    def resolution(self) -> float:
        """Get the resolution (LSB value)."""
        return 2 ** -self.frac_bits

    def quantize(self, new_word_length: int, new_frac_bits: int,
                rounding: str = 'convergent') -> 'FixedPointArray':
        """
        Quantize array to a different fixed-point format.

        Args:
            new_word_length: New word length
            new_frac_bits: New number of fractional bits
            rounding: Rounding mode ('convergent', 'round', 'truncate')

        Returns:
            FixedPointArray: Quantized array
        """
        shift = self.frac_bits - new_frac_bits

        if shift > 0:
            # Reduce fractional bits
            if rounding == 'truncate':
                new_raw = self.raw_values >> shift
            elif rounding == 'round':
                new_raw = (self.raw_values + (1 << (shift - 1))) >> shift
            elif rounding == 'convergent':
                # Vectorized convergent rounding
                half = 1 << (shift - 1)
                mask = (1 << shift) - 1
                remainder = self.raw_values & mask
                shifted = self.raw_values >> shift

                # Round half to even
                round_up = (remainder > half) | ((remainder == half) & (shifted & 1))
                new_raw = shifted + round_up.astype(np.int64)
            else:
                raise ValueError(f"Unknown rounding mode: {rounding}")
        elif shift < 0:
            new_raw = self.raw_values << (-shift)
        else:
            new_raw = self.raw_values.copy()

        result = FixedPointArray.__new__(FixedPointArray)
        result.word_length = new_word_length
        result.frac_bits = new_frac_bits
        result.signed = self.signed
        result.int_bits = new_word_length - new_frac_bits - (1 if self.signed else 0)
        result.raw_values = result._saturate(new_raw)

        return result

    def __repr__(self) -> str:
        """String representation."""
        sign_str = 's' if self.signed else 'u'
        return (f"FixedPointArray(shape={self.raw_values.shape}, "
                f"{sign_str}Q{self.int_bits}.{self.frac_bits})")


def calculate_sqnr(original: np.ndarray, quantized: np.ndarray) -> float:
    """
    Calculate Signal-to-Quantization-Noise Ratio (SQNR).

    SQNR = 10 * log10(signal_power / noise_power)

    Args:
        original: Original floating-point signal
        quantized: Quantized signal

    Returns:
        float: SQNR in dB
    """
    signal_power = np.mean(original ** 2)
    noise = original - quantized
    noise_power = np.mean(noise ** 2)

    if noise_power < 1e-12:
        return 120.0  # Effectively infinite SQNR

    sqnr_db = 10 * np.log10(signal_power / noise_power)
    return sqnr_db


def demo():
    """Demonstration of fixed-point arithmetic."""
    print("=== Fixed-Point Arithmetic Demo ===\n")

    # Test s16.15 format
    print("--- s16.15 Format ---")
    fp1 = FixedPoint(0.5, word_length=16, frac_bits=15, signed=True)
    fp2 = FixedPoint(-0.25, word_length=16, frac_bits=15, signed=True)

    print(f"fp1 = {fp1}")
    print(f"fp2 = {fp2}")
    print(f"Resolution: {fp1.resolution:.10f}")
    print(f"Range: [{fp1.min_value}, {fp1.max_value}]")

    # Addition
    fp3 = fp1 + fp2
    print(f"\nfp1 + fp2 = {fp3.value} (expected: 0.25)")

    # Multiplication
    fp4 = fp1 * fp2
    print(f"fp1 * fp2 = {fp4.value} (expected: -0.125)")

    # Quantization with different rounding modes
    print("\n--- Quantization Test ---")
    original = FixedPoint(0.12345, word_length=32, frac_bits=16)
    print(f"Original (32-bit): {original.value}")

    q_trunc = original.quantize(16, 15, rounding='truncate')
    q_round = original.quantize(16, 15, rounding='round')
    q_conv = original.quantize(16, 15, rounding='convergent')

    print(f"Truncate: {q_trunc.value}")
    print(f"Round: {q_round.value}")
    print(f"Convergent: {q_conv.value}")

    # Test saturation
    print("\n--- Saturation Test ---")
    over = FixedPoint(2.0, word_length=16, frac_bits=15, signed=True)
    under = FixedPoint(-2.0, word_length=16, frac_bits=15, signed=True)

    print(f"2.0 saturated to: {over.value} (max: {over.max_value})")
    print(f"-2.0 saturated to: {under.value} (min: {under.min_value})")

    # Test array operations
    print("\n--- Fixed-Point Array Demo ---")
    signal = np.sin(2*np.pi*np.linspace(0, 1, 100))
    fp_array = FixedPointArray(signal, word_length=16, frac_bits=15)

    print(f"Array shape: {fp_array.raw_values.shape}")
    print(f"Format: s{fp_array.word_length}.{fp_array.frac_bits}")

    # Calculate SQNR
    sqnr = calculate_sqnr(signal, fp_array.values)
    print(f"SQNR: {sqnr:.2f} dB")

    # Theoretical SQNR
    theoretical_sqnr = 6.02 * 16 + 1.76
    print(f"Theoretical SQNR (16-bit): {theoretical_sqnr:.2f} dB")

    print("\n=== Demo Complete ===")


if __name__ == "__main__":
    demo()

"""
Signal Generation and Analysis Utilities

This module provides utility functions for generating test signals and
analyzing frequency responses for testing the DFE filter system.
"""

import numpy as np
from typing import List, Tuple
from math import pi
from matplotlib import pyplot as plt
from numpy.fft import fft, fftshift

def generate_signal(frequencies: List[float], fs: float, stop_time: float = 3.0) -> Tuple[np.ndarray, np.ndarray]:
    """
    Generate a time-domain signal composed of multiple sinusoids.

    Parameters:
    -----------
    frequencies : list of float
        Frequencies of sinusoids in Hz.
    fs : float
        Sampling frequency in Hz.
    stop_time : float
        Signal duration in seconds.

    Returns:
    --------
    t : ndarray
        Time array.
    x_n : ndarray
        Generated signal.
    """
    t = np.arange(0, stop_time, 1 / fs)
    x_n = np.sum([np.sin(2 * pi * f * t) for f in frequencies], axis=0)
    return t, x_n

def measure_passband_ripple(freqs, response, passband_end=2.8e6):
    """
    Measure passband ripple in dB (peak-to-peak difference).

    Parameters:
    -----------
    freqs : ndarray
        Frequency points in Hz.
    response : ndarray
        Magnitude response (linear or dB scale).
    passband_end : float
        Upper frequency of passband in Hz.

    Returns:
    --------
    ripple_db : float
        Passband ripple in dB.
    """
    passband_mask = (freqs >= 0) & (freqs <= passband_end)
    passband_response = response[passband_mask]
    if np.max(passband_response) > 1:
        mag_db = 20 * np.log10(passband_response)
    else:
        mag_db = passband_response
    ripple_db = np.max(mag_db) - np.min(mag_db)
    return ripple_db

def measure_stopband_attenuation(freqs, response, stopband_start=3.2e6):
    """
    Measure minimum stopband attenuation in dB.

    Parameters:
    -----------
    freqs : ndarray
        Frequency points in Hz.
    response : ndarray
        Magnitude response (linear or dB scale).
    stopband_start : float
        Lower frequency of stopband in Hz.

    Returns:
    --------
    attenuation_db : float
        Minimum stopband attenuation in dB.
    """
    stopband_mask = freqs >= stopband_start
    stopband_response = response[stopband_mask]
    if np.max(stopband_response) > 1:
        mag_db = 20 * np.log10(stopband_response)
    else:
        mag_db = stopband_response
    attenuation_db = -np.max(mag_db)
    return attenuation_db

def compute_frequency_response(signal, fs):
    """
    Compute frequency points and normalized magnitude response of a signal.

    Parameters:
    -----------
    signal : ndarray
        Time-domain signal.
    fs : float
        Sampling frequency.

    Returns:
    --------
    freqs : ndarray
        Frequency points (Hz).
    mag_response : ndarray
        Normalized magnitude response (linear scale).
    """
    n = len(signal)
    freqs = np.fft.rfftfreq(n, 1/fs)
    fft_vals = np.fft.rfft(signal)
    mag_response = np.abs(fft_vals) / np.max(np.abs(fft_vals))
    return freqs, mag_response

def check_signal_passband_stopband(signal, fs, passband_end=2.8e6, stopband_start=3.2e6):
    """
    Check passband ripple and stopband attenuation of signal.

    Parameters:
    -----------
    signal : ndarray
        Input signal.
    fs : float
        Sampling frequency.
    passband_end : float
        Passband frequency upper bound (Hz).
    stopband_start : float
        Stopband frequency lower bound (Hz).

    Returns:
    --------
    ripple_db : float
        Passband ripple in dB.
    attenuation_db : float
        Stopband attenuation in dB.
    """
    freqs, mag_response = compute_frequency_response(signal, fs)
    ripple_db = measure_passband_ripple(freqs, mag_response, passband_end)
    attenuation_db = measure_stopband_attenuation(freqs, mag_response, stopband_start)
    return ripple_db, attenuation_db

def plot_signal_and_spectrum(x_n: np.ndarray,
                             fs: float,
                             frequencies: List[float],
                             fft_len: int = 1024,
                             stop_time: float = 3.0,
                             title_prefix: str = "Input") -> Tuple[plt.Figure, plt.Axes]:
    """
    Plot time-domain signal and normalized dB FFT spectrum with aliasing frequency annotations.

    Parameters:
    -----------
    x_n : ndarray
        Signal samples.
    fs : float
        Sampling frequency in Hz.
    frequencies : list
        Signal frequency components.
    fft_len : int
        FFT length.
    stop_time : float
        Signal duration in seconds.
    title_prefix : str
        Prefix for plot titles.

    Returns:
    --------
    fig, axes : Matplotlib figure and axes objects.
    """
    t = np.arange(len(x_n)) / fs
    nyquist = fs/2
    zone1_freqs = [f for f in frequencies if 0 <= f <= nyquist]
    zone2_freqs = [f for f in frequencies if nyquist < f <= fs]
    zone3_freqs = [f for f in frequencies if f > fs]
    show_zone2 = len(zone2_freqs) > 0
    show_zone3 = len(zone3_freqs) > 0

    X_k = fftshift(np.abs(fft(x_n, fft_len)))
    X_k = X_k / np.max(X_k)
    X_k_db = 20 * np.log10(X_k + 1e-12)
    freq = np.linspace(-fs/2, fs/2, fft_len)

    fig, axes = plt.subplots(2, 1, figsize=(14, 8))
    n_samples = min(500, len(t))
    axes[0].plot(t[:n_samples], x_n[:n_samples])
    axes[0].set_xlabel("Time (s)")
    axes[0].set_ylabel("Amplitude")
    axes[0].set_title(f"{title_prefix} Signal with Frequencies: {frequencies} Hz")
    axes[0].grid(True, alpha=0.3)

    axes[1].plot(freq, X_k_db)
    axes[1].set_xlabel("FFT Frequency (Hz)")
    axes[1].set_ylabel("Magnitude (dB)")
    axes[1].set_title(f"{title_prefix} FFT Spectrum with Aliased Frequencies (Normalized dB)")
    axes[1].set_ylim([-100, 5])
    axes[1].grid(True, alpha=0.3)

    for i, fx in enumerate(zone1_freqs):
        axes[1].axvline(fx, color='green', linestyle='-', label='Zone 1 True Freq' if i == 0 else None)
        axes[1].axvline(-fx, color='green', linestyle='-', alpha=0.5)
    if show_zone2:
        for i, fx in enumerate(zone2_freqs):
            aliased = abs(((fx + fs/2) % fs) - fs/2)
            axes[1].axvline(fx, color='orange', linestyle='--', label='Zone 2 True Freq' if i == 0 else None)
            axes[1].axvline(aliased, color='red', linestyle=':', label='Zone 2 Aliased Freq' if i == 0 else None)
    if show_zone3:
        for i, fx in enumerate(zone3_freqs):
            aliased = abs(((fx + fs/2) % fs) - fs/2)
            axes[1].axvline(fx, color='purple', linestyle='--', label='Zone 3 True Freq' if i == 0 else None)
            axes[1].axvline(aliased, color='pink', linestyle=':', label='Zone 3 Aliased Freq' if i == 0 else None)
    axes[1].axvline(fs/2, color='k', linestyle='--', label='Nyquist +fs/2')
    axes[1].axvline(-fs/2, color='k', linestyle='--', label='Nyquist -fs/2')
    axes[1].legend(fontsize=8, loc='upper right')
    plt.tight_layout()
    return fig, axes

def compare_input_output_spectrum(input_signal: np.ndarray,
                                  output_signal: np.ndarray,
                                  fs_in: float,
                                  fs_out: float,
                                  frequencies: List[float],
                                  fft_len: int = 2048,
                                  title: str = "Input vs Output Spectrum") -> plt.Figure:
    """
    Compare normalized dB spectra of input and output signals side-by-side.

    Parameters:
    -----------
    input_signal : ndarray
        Input time-domain samples.
    output_signal : ndarray
        Output time-domain samples.
    fs_in : float
        Input sampling frequency.
    fs_out : float
        Output sampling frequency.
    frequencies : list
        Expected frequency components of the input signal.
    fft_len : int
        FFT length.
    title : str
        Plot title.

    Returns:
    --------
    matplotlib.figure.Figure
        Figure object with the plots.
    """
    X_in = fftshift(np.abs(fft(input_signal, fft_len)))
    X_out = fftshift(np.abs(fft(output_signal, fft_len)))
    X_in = X_in / np.max(X_in)
    X_out = X_out / np.max(X_out)
    X_in_db = 20 * np.log10(X_in + 1e-12)
    X_out_db = 20 * np.log10(X_out + 1e-12)

    freq_in = np.linspace(-fs_in/2, fs_in/2, fft_len)
    freq_out = np.linspace(-fs_out/2, fs_out/2, fft_len)

    fig, axes = plt.subplots(2, 1, figsize=(14, 10))
    axes[0].plot(freq_in / 1e6, X_in_db, 'b-', linewidth=1)
    axes[0].set_xlabel("Frequency (MHz)")
    axes[0].set_ylabel("Magnitude (dB)")
    axes[0].set_title(f"{title} - Input @ {fs_in/1e6:.1f} MHz")
    axes[0].grid(True, alpha=0.3)
    axes[0].set_ylim([-100, 5])
    for f in frequencies:
        if f <= fs_in / 2:
            axes[0].axvline(f/1e6, color='r', linestyle='--', alpha=0.5)
            axes[0].axvline(-f/1e6, color='r', linestyle='--', alpha=0.5)

    axes[1].plot(freq_out / 1e6, X_out_db, 'g-', linewidth=1)
    axes[1].set_xlabel("Frequency (MHz)")
    axes[1].set_ylabel("Magnitude (dB)")
    axes[1].set_title(f"{title} - Output @ {fs_out/1e6:.1f} MHz")
    axes[1].grid(True, alpha=0.3)
    axes[1].set_ylim([-100, 5])
    for f in frequencies:
        if f <= fs_out / 2:
            axes[1].axvline(f/1e6, color='r', linestyle='--', alpha=0.5)
            axes[1].axvline(-f/1e6, color='r', linestyle='--', alpha=0.5)

    plt.tight_layout()
    return fig

import matplotlib.pyplot as plt

def check_aliasing_suppression(input_freqs: List[float],
                               input_signal: np.ndarray,
                               output_signal: np.ndarray,
                               fs_in: float,
                               fs_out: float,
                               fft_len: int = 4096,
                               plot: bool = True) -> dict:
    """
    Check aliasing suppression and optionally plot spectra with alias markers.

    Parameters:
    -----------
    input_freqs : list
        Original input frequencies.
    input_signal : ndarray
        Input time-domain signal.
    output_signal : ndarray
        Output time-domain signal.
    fs_in : float
        Input sampling frequency.
    fs_out : float
        Output sampling frequency.
    fft_len : int
        FFT length.
    plot : bool
        If True, plot input/output spectra with aliasing lines.

    Returns:
    --------
    results : dict
        Dictionary containing aliasing suppression analysis.
    """
    X_in = fftshift(np.abs(fft(input_signal, fft_len)))
    X_out = fftshift(np.abs(fft(output_signal, fft_len)))

    X_in = X_in / np.max(X_in)
    X_out = X_out / np.max(X_out)

    X_in_db = 20 * np.log10(X_in + 1e-12)
    X_out_db = 20 * np.log10(X_out + 1e-12)

    freq_in = np.linspace(-fs_in / 2, fs_in / 2, fft_len)
    freq_out = np.linspace(-fs_out / 2, fs_out / 2, fft_len)

    nyquist_out = fs_out / 2
    aliased_freqs = [f for f in input_freqs if f > nyquist_out]

    results = {
        'input_freqs': input_freqs,
        'output_nyquist': nyquist_out,
        'aliased_freqs': aliased_freqs,
        'num_aliased': len(aliased_freqs),
        'aliasing_suppression': {}
    }

    print("Aliasing suppression results:")
    for f in aliased_freqs:
        alias_freq = abs(((f + nyquist_out) % fs_out) - nyquist_out)
        alias_idx = np.argmin(np.abs(freq_out - alias_freq))
        alias_power_db = X_out_db[alias_idx]
        results['aliasing_suppression'][f] = {
            'original_freq_hz': f,
            'alias_freq_hz': alias_freq,
            'alias_power_db': alias_power_db
        }

        print(f"Input freq {f/1e6} MHz aliased at {alias_freq/1e6} MHz "
              f"with power {alias_power_db} dB")

    if plot:
        fig, axes = plt.subplots(2, 1, figsize=(14, 9), sharex=True)

        # Plot input spectrum
        axes[0].plot(freq_in / 1e6, X_in_db, label='Input Spectrum')
        axes[0].set_title('Input Signal Spectrum with Aliasing Frequencies')
        axes[0].set_ylabel('Magnitude (dB)')
        axes[0].grid(True, alpha=0.3)
        axes[0].set_ylim([-100, 5])

        # Mark input frequencies and alias lines
        for f in input_freqs:
            axes[0].axvline(f / 1e6, color='r', linestyle='--', alpha=0.6,
                            label='Input Frequency' if f == input_freqs[0] else None)
            axes[0].axvline(-f / 1e6, color='r', linestyle='--', alpha=0.6)

        # Plot output spectrum
        axes[1].plot(freq_out / 1e6, X_out_db, label='Output Spectrum')
        axes[1].set_title('Output Signal Spectrum with Aliased Frequencies')
        axes[1].set_ylabel('Magnitude (dB)')
        axes[1].set_xlabel('Frequency (MHz)')
        axes[1].grid(True, alpha=0.3)
        axes[1].set_ylim([-100, 5])

        for f in aliased_freqs:
            alias_freq = results['aliasing_suppression'][f]['alias_freq_hz']
            axes[1].axvline(f / 1e6, color='orange', linestyle='-', alpha=0.7,
                            label='Aliased Frequency Input' if f == aliased_freqs[0] else None)
            axes[1].axvline(alias_freq / 1e6, color='purple', linestyle='--', alpha=0.7,
                            label='Aliased Frequency Output' if f == aliased_freqs[0] else None)

        axes[1].legend(fontsize=8)
        axes[0].legend(fontsize=8)

        plt.tight_layout()
        plt.show()

    return results



# ========== DEMO/TEST ==========
if __name__ == "__main__":
    # Frequencies for test signal (in Hz): some in passband, some in stopband range
    frequencies = [1e6, 2.5e6, 3.5e6, 10e6]

    # Sampling frequency (Hz)
    fs = 9e6

    # Generate signal (3 ms duration)
    t, input_signal = generate_signal(frequencies, fs, stop_time=3e-3)

    # Analyze input signal
    ripple, attenuation = check_signal_passband_stopband(input_signal, fs)

    print(f"Passband ripple (dB): {ripple:.4f}")
    print(f"Stopband attenuation (dB): {attenuation:.4f}")

    # Plot time-domain and spectrum of input signal
    fig1, axes1 = plot_signal_and_spectrum(input_signal, fs, frequencies,
                                          fft_len=2048, stop_time=3e-3, title_prefix="Input Signal")
    plt.show()

    # Suppose we have an output signal (for example, after filtering/processing)
    # For demonstration, simulate output as a low-pass filtered version (simple ideal)
    def lowpass_filter(signal, cutoff_freq, fs):
        from scipy.signal import butter, filtfilt
        nyq = fs / 2
        b, a = butter(6, cutoff_freq / nyq, btype='low')
        return filtfilt(b, a, signal)

    cutoff_frequency = 3e6  # 3 MHz cutoff
    output_signal = lowpass_filter(input_signal, cutoff_frequency, fs)

    # Analyze output signal
    ripple_out, attenuation_out = check_signal_passband_stopband(output_signal, fs)

    print(f"Output Passband ripple (dB): {ripple_out:.4f}")
    print(f"Output Stopband attenuation (dB): {attenuation_out:.4f}")

    # Plot input vs output spectrum comparison
    fig2 = compare_input_output_spectrum(input_signal, output_signal, fs, fs, frequencies,
                                        fft_len=2048, title="Filter Input vs Output Spectrum")
    plt.show()

    # Analyze input signal
    ripple, attenuation = check_signal_passband_stopband(input_signal, fs)

    print(f"Passband ripple (dB): {ripple:.4f}")
    print(f"Stopband attenuation (dB): {attenuation:.4f}")
    # Analyze input signal
    ripple, attenuation = check_signal_passband_stopband(output_signal, fs)

    print(f"Passband ripple (dB): {ripple:.4f}")
    print(f"Stopband attenuation (dB): {attenuation:.4f}")




    # Check aliasing suppression in output relative to input frequencies and sampling rates
    alias_results = check_aliasing_suppression(frequencies, input_signal, output_signal, fs, fs, fft_len=4096)