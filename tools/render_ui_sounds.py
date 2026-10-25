"""Renders VIMO's UI sound set (stand-in for the earshot toolkit).

One family: soft sine/bell partials, fast attacks with no click, quiet
peaks (about -20 dBFS for frequent sounds, -14 dBFS for success/notify),
short tails. 44.1 kHz, 16-bit mono WAV.

    python3 tools/render_ui_sounds.py assets/sounds
"""
import sys, wave, struct
import numpy as np

SR = 44100
rng = np.random.default_rng(7)


def env(n, attack=0.002, decay=0.08):
    t = np.arange(n) / SR
    a = np.clip(t / attack, 0, 1)
    # raised-cosine attack avoids clicks
    a = 0.5 - 0.5 * np.cos(np.pi * a)
    return a * np.exp(-t / decay)


def tone(freq, dur, decay, partials=((1, 1.0),), attack=0.002, glide=0.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = freq * (1 + glide * t / dur)
    phase = 2 * np.pi * np.cumsum(f) / SR
    out = np.zeros(n)
    for mult, amp in partials:
        # higher partials die faster, like a struck bell
        out += amp * np.sin(phase * mult) * np.exp(-t / (decay / mult ** 0.6))
    a = np.clip(t / attack, 0, 1)
    return out * (0.5 - 0.5 * np.cos(np.pi * a))


def noise(dur, decay, lo, hi, attack=0.003):
    n = int(SR * dur)
    x = rng.standard_normal(n)
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    spec[(freqs < lo) | (freqs > hi)] = 0
    y = np.fft.irfft(spec, n)
    y /= np.max(np.abs(y)) + 1e-9
    return y * env(n, attack, decay)


def place(buf, sig, at):
    i = int(at * SR)
    buf[i:i + len(sig)] += sig[: len(buf) - i]


def finish(x, peak_db):
    # 4 ms fade out at the end, normalise to the target peak
    fade = int(0.004 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)
    return x


def write(path, x):
    data = (np.clip(x, -1, 1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


BELL = ((1, 1.0), (2.0, 0.28), (3.01, 0.10), (4.2, 0.04))
SOFT = ((1, 1.0), (2.0, 0.12))


def tap():
    x = np.zeros(int(SR * 0.05))
    place(x, tone(2350, 0.04, 0.010, SOFT, attack=0.0008), 0)
    place(x, 0.35 * noise(0.03, 0.006, 1800, 7000, attack=0.0005), 0)
    return finish(x, -22)


def toggle(up):
    x = np.zeros(int(SR * 0.11))
    a, b = (1046.5, 1318.5) if up else (1318.5, 1046.5)  # C6 / E6
    place(x, tone(a, 0.06, 0.022, SOFT), 0)
    place(x, tone(b, 0.07, 0.026, SOFT), 0.035)
    return finish(x, -21)


def success():
    x = np.zeros(int(SR * 0.62))
    place(x, tone(1318.5, 0.6, 0.20, BELL), 0)        # E6
    place(x, 0.8 * tone(1975.5, 0.5, 0.18, BELL), 0.075)  # B6, a fifth up
    return finish(x, -15)


def error():
    x = np.zeros(int(SR * 0.2))
    place(x, tone(150, 0.18, 0.05, ((1, 1.0), (2, 0.25)), attack=0.003, glide=-0.35), 0)
    place(x, 0.25 * noise(0.06, 0.02, 60, 900), 0)
    place(x, 0.6 * tone(118, 0.16, 0.045, SOFT, attack=0.003, glide=-0.3), 0.07)
    return finish(x, -16)


def whoosh():
    n = int(SR * 0.22)
    x = rng.standard_normal(n)
    # sweep a band-pass by blending two filtered copies over time
    lo = np.fft.irfft(np.fft.rfft(x) * (np.fft.rfftfreq(n, 1 / SR) < 1400), n)
    hi = np.fft.irfft(np.fft.rfft(x) * ((np.fft.rfftfreq(n, 1 / SR) > 1200) & (np.fft.rfftfreq(n, 1 / SR) < 5200)), n)
    t = np.linspace(0, 1, n)
    y = lo * (1 - t) + hi * t
    shape = np.sin(np.pi * np.clip(t, 0, 1)) ** 1.6
    return finish(y * shape, -26)


def notification():
    x = np.zeros(int(SR * 0.8))
    place(x, tone(783.99, 0.7, 0.24, BELL), 0)       # G5
    place(x, tone(1046.5, 0.7, 0.26, BELL), 0.12)    # C6
    return finish(x, -16)


SOUNDS = {
    'tap.wav': tap,
    'toggle_on.wav': lambda: toggle(True),
    'toggle_off.wav': lambda: toggle(False),
    'success.wav': success,
    'error.wav': error,
    'whoosh.wav': whoosh,
    'notification.wav': notification,
}

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else 'assets/sounds'
    for name, make in SOUNDS.items():
        write(f'{out}/{name}', make())
        print(name)
