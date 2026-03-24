##############################################################################
# HYBRID INT8 INFERENCE (RTL Layer1 + TFLite rest)
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

INPUT_IDX = 0
WEIGHT_IDX = 64
BIAS_IDX = 63
CONV65_IDX = 65
RELU66_IDX = 66
OUTPUT_IDX = output_details[0]['index']

# -------------------------
# QUANT PARAMS
# -------------------------

input_scale, input_zero = td[INPUT_IDX]['quantization']
conv_scale, conv_zero = td[CONV65_IDX]['quantization']
relu_scale, relu_zero = td[RELU66_IDX]['quantization']

print("Input quant:", input_scale, input_zero)
print("Conv quant:", conv_scale, conv_zero)
print("ReLU quant:", relu_scale, relu_zero)

# -------------------------
# LOAD WEIGHTS
# -------------------------

weights = interpreter.get_tensor(WEIGHT_IDX)
bias = interpreter.get_tensor(BIAS_IDX).astype(np.int32)

# -------------------------
# LOAD RTL QUANT PARAMS
# -------------------------

def load_mem_1d(filename, signed=True):
    vals = []
    with open(filename) as f:
        for line in f:
            v = int(line.strip(), 16)
            if signed and v >= (1 << 31):
                v -= (1 << 32)
            vals.append(v)
    return np.array(vals, dtype=np.int32)

def load_mem_shift(filename):
    vals = []
    with open(filename) as f:
        for line in f:
            v = int(line.strip(), 16)
            if v >= 32:
                v -= 64
            vals.append(v)
    return np.array(vals, dtype=np.int32)

conv_qm     = load_mem_1d("conv_qm.mem")
conv_shift  = load_mem_shift("conv_shift.mem")

relu_pos_qm    = load_mem_1d("relu_pos_qm.mem")[0]
relu_pos_shift = load_mem_shift("relu_pos_shift.mem")[0]

relu_neg_qm    = load_mem_1d("relu_neg_qm.mem")[0]
relu_neg_shift = load_mem_shift("relu_neg_shift.mem")[0]

# -------------------------
# BIT-ACCURATE FUNCTIONS
# -------------------------

INT32_MIN = -2**31
INT32_MAX =  2**31 - 1

def high_mul(a, b):
    if a == INT32_MIN and b == INT32_MIN:
        return INT32_MAX
    ab = int(a) * int(b)
    nudge = (1 << 30) if ab >= 0 else ((1 << 30) - 1)
    return int((ab + nudge) >> 31)

def div_pot(x, shift):
    mask = (1 << shift) - 1
    remainder = x & mask
    threshold = mask >> 1
    if x < 0:
        threshold += 1
    result = x >> shift
    if remainder > threshold:
        result += 1
    return result

def mul_q(x, qm, shift):
    if shift > 0:
        return high_mul(x << shift, qm)
    elif shift < 0:
        return div_pot(high_mul(x, qm), -shift)
    else:
        return high_mul(x, qm)

# -------------------------
# RTL-ACCURATE LAYER1
# -------------------------

def run_layer1_rtl(img):

    H, W, IC = img.shape
    OC, KH, KW, _ = weights.shape

    ph, pw = KH//2, KW//2

    img_pad = np.pad(
        img.astype(np.int32),
        ((ph, ph), (pw, pw), (0, 0)),
        mode='constant',
        constant_values=input_zero
    )

    out = np.zeros((H, W, OC), dtype=np.int8)

    for h in range(H):
        for w in range(W):
            for oc in range(OC):

                acc = 0

                for ky in range(KH):
                    for kx in range(KW):
                        for ic in range(IC):

                            pix = img_pad[h+ky, w+kx, ic] - input_zero
                            wt  = weights[oc, ky, kx, ic]

                            acc += pix * wt

                acc += bias[oc]

                # -------- Requant --------
                rq = mul_q(acc, conv_qm[oc], conv_shift[oc])
                rq = rq + conv_zero
                rq = max(-128, min(127, rq))

                # -------- LeakyReLU --------
                centered = rq - conv_zero

                if centered >= 0:
                    scaled = mul_q(centered, relu_pos_qm, relu_pos_shift)
                else:
                    scaled = mul_q(centered, relu_neg_qm, relu_neg_shift)

                val = scaled + relu_zero
                val = max(-128, min(127, val))

                out[h, w, oc] = np.int8(val)

    return out

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

    data_scaled, mag, phase = convert_to_stft(frame)

    input_int8 = (data_scaled / input_scale + input_zero).astype(np.int8)

    # 🔥 RTL layer1
    tensor66 = run_layer1_rtl(input_int8[0])

    # inject
    interpreter.set_tensor(INPUT_IDX, input_int8)
    interpreter.set_tensor(RELU66_IDX, np.expand_dims(tensor66, axis=0))

    interpreter.invoke()

    output_int8 = interpreter.get_tensor(OUTPUT_IDX)

    output_scale, output_zero = output_details[0]['quantization']

    predicted_clean = (output_int8.astype(np.float32) - output_zero) * output_scale
    predicted_clean = predicted_clean.reshape(predicted_clean.shape[1], predicted_clean.shape[2])

    audio_out = convert_to_time_domain(predicted_clean, phase, CHUNK)

    return audio_out[:original_len]

# -------------------------
# RUN
# -------------------------

audio, _ = librosa.load("/content/noisy_data/noisy_testset_wav/p232_001.wav", sr=RATE)

frames = [audio[i:i+CHUNK] for i in range(0, len(audio), CHUNK)]

clean_frames = []

for i, frame in enumerate(frames):
    print("Processing frame", i+1)
    clean_frames.append(run_denoiser_hybrid(frame))

clean_audio = np.concatenate(clean_frames)

sf.write("denoised_hybrid.wav", clean_audio, RATE)

print("✅ Saved: denoised_hybrid.wav")