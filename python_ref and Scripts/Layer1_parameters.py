
# Generation of biases,weights and other parameters for RTL Layer1
import numpy as np
import math
import tensorflow as tf

MODEL_PATH = "voicebank_denoiser_int8.tflite"

interpreter = tf.lite.Interpreter(
    model_path=MODEL_PATH,
    experimental_preserve_all_tensors=True
)
interpreter.allocate_tensors()
td = interpreter.get_tensor_details()

# --------------------------------------------------
# Tensor indices (same as your setup)
# --------------------------------------------------
INPUT_IDX = 0
WEIGHT_IDX = 64
BIAS_IDX = 63
CONV_IDX = 65
RELU_IDX = 66

# --------------------------------------------------
# Quant params
# --------------------------------------------------
i_scale, i_zero = td[INPUT_IDX]["quantization"]
conv_scale, conv_zero = td[CONV_IDX]["quantization"]
relu_scale, relu_zero = td[RELU_IDX]["quantization"]

weights = interpreter.get_tensor(WEIGHT_IDX)
bias = interpreter.get_tensor(BIAS_IDX).astype(np.int32)

w_scales = np.array(td[WEIGHT_IDX]["quantization_parameters"]["scales"])

# --------------------------------------------------
# Quantization helpers
# --------------------------------------------------
def quantize_multiplier(real_multiplier):
    if real_multiplier == 0:
        return 0, 0

    shift = 0

    # Normalize to [0.5, 1)
    while real_multiplier < 0.5:
        real_multiplier *= 2.0
        shift -= 1

    while real_multiplier >= 1.0:
        real_multiplier /= 2.0
        shift += 1

    qm = int(round(real_multiplier * (1 << 31)))

    if qm == (1 << 31):
        qm //= 2
        shift += 1

    return qm, shift

# --------------------------------------------------
# Generate CONV multipliers
# --------------------------------------------------
NUM_FILTERS = weights.shape[0]

conv_qm = []
conv_shift = []

for oc in range(NUM_FILTERS):
    rm = (i_scale * w_scales[oc]) / conv_scale
    qm, shift = quantize_multiplier(rm)

    conv_qm.append(qm)
    conv_shift.append(shift)

# --------------------------------------------------
# Generate LeakyReLU multipliers
# --------------------------------------------------
slope = 0.3

pos_rm = conv_scale / relu_scale
neg_rm = (conv_scale * slope) / relu_scale

relu_pos_qm, relu_pos_shift = quantize_multiplier(pos_rm)
relu_neg_qm, relu_neg_shift = quantize_multiplier(neg_rm)

# --------------------------------------------------
# SAVE .mem FILES
# --------------------------------------------------

def write_mem_1d(filename, arr, fmt="hex"):
    with open(filename, "w") as f:
        for x in arr:
            x = int(x)   # 🔥 CRITICAL FIX

            if fmt == "hex":
                if x < 0:
                    x = (1 << 32) + x
                f.write(f"{x:08x}\n")
            else:
                f.write(f"{x}\n")

def write_mem_2d(filename, arr):
    with open(filename, "w") as f:
        for row in arr:
            for val in row:
                v = int(val)
                if v < 0:
                    v = (1 << 8) + v
                f.write(f"{v:02x}\n")

# Weights: [OC][9]
weights_reshaped = weights.reshape(weights.shape[0], -1)
write_mem_2d("weights.mem", weights_reshaped)

# Bias
write_mem_1d("bias.mem", bias)

# Conv quant
write_mem_1d("conv_qm.mem", conv_qm)
write_mem_1d("conv_shift.mem", conv_shift, fmt="hex")

# ReLU quant (scalars → still saved as 1-line mem)
write_mem_1d("relu_pos_qm.mem", [relu_pos_qm])
write_mem_1d("relu_pos_shift.mem", [relu_pos_shift], fmt="dec")

write_mem_1d("relu_neg_qm.mem", [relu_neg_qm])
write_mem_1d("relu_neg_shift.mem", [relu_neg_shift], fmt="dec")

# --------------------------------------------------
# OPTIONAL: INPUT GENERATION (padded)
# --------------------------------------------------

def write_input_mem(input_int8, filename="input_padded.mem"):
    H, W = input_int8.shape
    padded = np.pad(input_int8, ((1,1),(1,1)), constant_values=i_zero)

    with open(filename, "w") as f:
        for v in padded.flatten():
            val = int(v)
            if val < 0:
                val = (1 << 8) + val
            f.write(f"{val:02x}\n")

# Example random input
input_int8 = np.random.randint(-128, 127, (128,128), dtype=np.int8)
write_input_mem(input_int8)

# --------------------------------------------------
# DEBUG PRINT
# --------------------------------------------------

print("\n=== GENERATED FILES ===")
print("weights.mem")
print("bias.mem")
print("conv_qm.mem")
print("conv_shift.mem")
print("relu_pos_qm.mem")
print("relu_pos_shift.mem")
print("relu_neg_qm.mem")
print("relu_neg_shift.mem")
print("input_padded.mem")

print("\n=== SAMPLE VALUES ===")
print("conv_qm[0] =", conv_qm[0])
print("conv_shift[0] =", conv_shift[0])
print("relu_pos_qm =", relu_pos_qm)
print("relu_neg_qm =", relu_neg_qm)