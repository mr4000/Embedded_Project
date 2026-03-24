#generate input_padded.mem file for RTL 

import numpy as np
import librosa
import tensorflow as tf

# -------------------------
# CONFIG
# -------------------------
MODEL_PATH = "voicebank_denoiser_int8.tflite"
AUDIO_PATH = "/content/noisy_data/noisy_testset_wav/p232_001.wav"

fftLength = 255
hop_length = 63
CHUNK = 8064

# -------------------------
# LOAD MODEL (for quant params)
# -------------------------
interpreter = tf.lite.Interpreter(
    model_path=MODEL_PATH,
    experimental_preserve_all_tensors=True
)
interpreter.allocate_tensors()
td = interpreter.get_tensor_details()

INPUT_IDX = 0
input_scale, input_zero = td[INPUT_IDX]["quantization"]

print("input_zero =", input_zero)

# -------------------------
# STFT → 128x128
# -------------------------
audio, _ = librosa.load(AUDIO_PATH, sr=22050)
audio = audio[:CHUNK]

stft = librosa.stft(audio, n_fft=fftLength, hop_length=hop_length)
mag = np.abs(stft)
mag_db = librosa.amplitude_to_db(mag, ref=1.0)

spec = mag_db[:128, :128]
spec_scaled = (spec + 80) / 80

# -------------------------
# QUANTIZE
# -------------------------
input_int8 = np.round(spec_scaled / input_scale + input_zero).astype(np.int8)

print("Input shape:", input_int8.shape)

# -------------------------
# SAVE PADDED MEM (130x130)
# -------------------------
padded = np.pad(input_int8, ((1,1),(1,1)), constant_values=input_zero)

with open("input_padded.mem", "w") as f:
    for v in padded.flatten():
        val = int(v)
        if val < 0:
            val = (1 << 8) + val
        f.write(f"{val:02x}\n")

print("Saved input_padded.mem")

# -------------------------
# DEBUG FIRST WINDOW
# -------------------------
print("\nFIRST WINDOW (Python):")
print(padded[0:3,0:3])
print("Flatten:", padded[0:3,0:3].flatten())