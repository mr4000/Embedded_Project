##############################################################################
# HYBRID INT8 INFERENCE (RTL DIRECT INJECTION - RAW)
##############################################################################

import numpy as np
import librosa
import soundfile as sf
import tensorflow as tf

# -------------------------
# PARAMETERS
# -------------------------

fftLength = 255
hop_length = 63
CHUNK = 8064
RATE = 22050

MODEL_PATH = "voicebank_denoiser_int8.tflite"
RTL_FILE   = "rtl_output.txt"

H = 128
W = 128
OC = 16

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
output_details = interpreter.get_output_details()

INPUT_IDX = input_details[0]['index']
RELU66_IDX = 66
OUTPUT_IDX = output_details[0]['index']

input_scale, input_zero = input_details[0]['quantization']

print("Input quant:", input_scale, input_zero)

# -------------------------
# RTL OUTPUT LOADER
# -------------------------

def load_rtl_output(filename):
    data = []

    with open(filename) as f:
        for line in f:
            for tok in line.strip().split():
                val = int(tok)

                # int8 wrap (in case file has unsigned values)
                if val > 127:
                    val -= 256
                if val < -128:
                    val += 256

                data.append(val)

    arr = np.array(data, dtype=np.int8)

    expected = H * W * OC
    print(f"RTL elements: {arr.size}, expected: {expected}")

    assert arr.size == expected, \
        f"❌ Size mismatch: got {arr.size}, expected {expected}"

    tensor = arr.reshape(H, W, OC)

    print("RTL shape:", tensor.shape)
    print("Min/Max:", tensor.min(), tensor.max())
    print("Sample [0,0]:", tensor[0,0,:])

    return tensor

# -------------------------
# STFT
# -------------------------

def convert_to_stft(data):
    stft = librosa.stft(data, n_fft=fftLength, hop_length=hop_length)
    mag, phase = librosa.magphase(stft)

    mag_db = librosa.amplitude_to_db(mag, ref=1.0)
    mag_scaled = (mag_db + 80) / 80

    return mag_scaled.reshape(1, mag_scaled.shape[0], mag_scaled.shape[1], 1), mag, phase

# -------------------------
# ISTFT
# -------------------------

def convert_to_time_domain(predicted_clean, phase, out_len):
    predicted_mag_db = (predicted_clean * 80) - 80
    predicted_mag = librosa.db_to_amplitude(predicted_mag_db, ref=1.0)

    predicted_stft = predicted_mag * phase

    return librosa.istft(predicted_stft, hop_length=hop_length, length=out_len)

# -------------------------
# HYBRID PIPELINE
# -------------------------

def run_denoiser_hybrid(frame):

    original_len = len(frame)

    if original_len < CHUNK:
        frame = np.pad(frame, (0, CHUNK - original_len))

    # STFT
    data_scaled, mag, phase = convert_to_stft(frame)

    # Quantize input
    input_int8 = (data_scaled / input_scale + input_zero).astype(np.int8)

    # Load RTL output (already int8)
    tensor66 = load_rtl_output(RTL_FILE)

    # Expand batch dimension
    tensor66 = np.expand_dims(tensor66, axis=0)

    # Inject
    interpreter.set_tensor(INPUT_IDX, input_int8)
    interpreter.set_tensor(RELU66_IDX, tensor66)

    # Run remaining graph
    interpreter.invoke()

    # Get output
    output_int8 = interpreter.get_tensor(OUTPUT_IDX)

    output_scale, output_zero = output_details[0]['quantization']

    predicted_clean = (output_int8.astype(np.float32) - output_zero) * output_scale

    predicted_clean = predicted_clean.reshape(
        predicted_clean.shape[1],
        predicted_clean.shape[2]
    )

    # ISTFT
    audio_out = convert_to_time_domain(predicted_clean, phase, CHUNK)

    return audio_out[:original_len]

# -------------------------
# RUN
# -------------------------

audio, _ = librosa.load(
    "/content/p257_029.wav",
    sr=RATE
)

frames = [audio[i:i+CHUNK] for i in range(0, len(audio), CHUNK)]

clean_frames = []

for i, frame in enumerate(frames):
    print("Processing frame", i+1)
    clean_frames.append(run_denoiser_hybrid(frame))

clean_audio = np.concatenate(clean_frames)

sf.write("denoised_rtl_injected.wav", clean_audio, RATE)

print("✅ Saved: denoised_rtl_injected.wav")
