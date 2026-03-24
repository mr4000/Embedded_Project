##############################################################################
# FULL RTL vs TFLITE DEBUG + DUMP (REAL AUDIO INPUT)
##############################################################################

import numpy as np
import tensorflow as tf
import librosa

# -------------------------
# CONFIG
# -------------------------

MODEL_PATH = "voicebank_denoiser_int8.tflite"
RTL_FILE   = "rtl_output.txt"
TFL_DUMP   = "tflite_ref.txt"

AUDIO_FILE = "/content/p257_029.wav"

H, W, OC = 128, 128, 16
RELU66_IDX = 66

fftLength = 255
hop_length = 63
CHUNK = 8064
RATE = 22050

# -------------------------
# LOAD MODEL
# -------------------------

interpreter = tf.lite.Interpreter(
    model_path=MODEL_PATH,
    experimental_preserve_all_tensors=True
)
interpreter.allocate_tensors()

td = interpreter.get_tensor_details()
input_details = interpreter.get_input_details()

INPUT_IDX = input_details[0]['index']
input_scale, input_zero = input_details[0]['quantization']

# -------------------------
# LOAD RTL OUTPUT
# -------------------------

def load_rtl():
    data = []
    with open(RTL_FILE) as f:
        for line in f:
            for tok in line.strip().split():
                val = int(tok)
                if val > 127: val -= 256
                if val < -128: val += 256
                data.append(val)

    arr = np.array(data, dtype=np.int8)
    assert arr.size == H*W*OC

    return arr.reshape(H, W, OC)

# -------------------------
# DUMP TFLITE LIKE RTL
# -------------------------

def dump_tflite_tensor_like_rtl(tensor, filename):
    if tensor.ndim == 4:
        tensor = tensor[0]

    with open(filename, "w") as f:
        for h in range(H):
            for w in range(W):
                row = tensor[h, w, :]
                f.write(" ".join(str(int(v)) for v in row) + "\n")

    print(f"✅ Saved TFLite reference: {filename}")

# -------------------------
# PREPARE REAL INPUT
# -------------------------

audio, _ = librosa.load(AUDIO_FILE, sr=RATE)

frame = audio[:CHUNK]

# pad if needed
if len(frame) < CHUNK:
    frame = np.pad(frame, (0, CHUNK - len(frame)))

# STFT
stft = librosa.stft(frame, n_fft=fftLength, hop_length=hop_length)
mag, phase = librosa.magphase(stft)

mag_db = librosa.amplitude_to_db(mag, ref=1.0)
mag_scaled = (mag_db + 80) / 80

data_scaled = mag_scaled.reshape(1, mag_scaled.shape[0], mag_scaled.shape[1], 1)

# quantize
input_int8 = (data_scaled / input_scale + input_zero).astype(np.int8)

# -------------------------
# RUN MODEL
# -------------------------

interpreter.set_tensor(INPUT_IDX, input_int8)
interpreter.invoke()

# -------------------------
# GET TFLITE OUTPUT
# -------------------------

tfl = interpreter.get_tensor(RELU66_IDX)
dump_tflite_tensor_like_rtl(tfl, TFL_DUMP)

tfl = tfl[0].astype(np.int32)
rtl = load_rtl().astype(np.int32)

# -------------------------
# BASIC STATS
# -------------------------

print("\n================ BASIC STATS ================")
print("TFL mean/std:", tfl.mean(), tfl.std())
print("RTL mean/std:", rtl.mean(), rtl.std())

# -------------------------
# DIFF
# -------------------------

diff = rtl - tfl
abs_diff = np.abs(diff)

print("\n================ DIFF STATS ================")
print("Max diff:", abs_diff.max())
print("Mean diff:", abs_diff.mean())

for th in [1,2,5,10,20,50]:
    print(f"<= {th}:", np.sum(abs_diff <= th))

# -------------------------
# CORRELATION
# -------------------------

corr = np.corrcoef(tfl.flatten(), rtl.flatten())[0,1]
print("\nCorrelation:", corr)

# -------------------------
# LINEAR FIT
# -------------------------

a = np.std(tfl) / (np.std(rtl) + 1e-8)
b = np.mean(tfl) - a * np.mean(rtl)

print("\n================ LINEAR FIT ================")
print("TFL ≈ a * RTL + b")
print("a:", a)
print("b:", b)

# -------------------------
# WORST ELEMENTS
# -------------------------

idx_flat = np.argsort(abs_diff.flatten())[::-1]

print("\n================ TOP 10 WORST ================")

for i in range(10):
    flat_idx = idx_flat[i]
    h, w, c = np.unravel_index(flat_idx, diff.shape)

    print(f"[h={h}, w={w}, c={c}] "
          f"TFL={tfl[h,w,c]} RTL={rtl[h,w,c]} "
          f"DIFF={diff[h,w,c]}")

# -------------------------
# FULL PIXEL VIEW
# -------------------------

print("\n================ WORST PIXELS FULL CHANNELS ================")

seen = set()

for i in range(20):
    flat_idx = idx_flat[i]
    h, w, c = np.unravel_index(flat_idx, diff.shape)

    if (h, w) in seen:
        continue
    seen.add((h, w))

    print(f"\n[h={h}, w={w}]")

    print("TFL :", tfl[h, w, :])
    print("RTL :", rtl[h, w, :])
    print("DIFF:", diff[h, w, :])

    if len(seen) == 5:
        break

# -------------------------
# CHANNEL ANALYSIS
# -------------------------

print("\n================ CHANNEL STATS ================")

for c in range(OC):
    tfl_c = tfl[:,:,c].flatten()
    rtl_c = rtl[:,:,c].flatten()

    mean_diff = np.mean(np.abs(tfl_c - rtl_c))
    corr_c = np.corrcoef(tfl_c, rtl_c)[0,1]

    print(f"Channel {c}: mean_diff={mean_diff:.2f}, corr={corr_c:.3f}")

# -------------------------
# RANGE
# -------------------------

print("\n================ RANGE ================")
print("TFL min/max:", tfl.min(), tfl.max())
print("RTL min/max:", rtl.min(), rtl.max())

print("\n✅ DONE")
