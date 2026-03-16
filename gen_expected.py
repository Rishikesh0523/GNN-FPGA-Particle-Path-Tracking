import numpy as np
import glob

# ==============================
# FIXED POINT HELPERS
# ==============================
def to_float(val, frac_bits, bits):
    """Convert signed int to float"""
    if val >= (1 << (bits - 1)):
        val -= (1 << bits)
    return val / (1 << frac_bits)

def to_fixed(val, frac_bits, bits):
    """Convert float to signed fixed"""
    val = int(round(val * (1 << frac_bits)))
    val = max(min(val, (1 << (bits-1))-1), -(1 << (bits-1)))
    return val

# ==============================
# LOAD MIF FILE
# ==============================
def load_mif_bin(filename, bits=8):
    data = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                val = int(line, 2)
                # convert to signed
                if val >= (1 << (bits - 1)):
                    val -= (1 << bits)
                data.append(val)
    return data

# ==============================
# LOAD WEIGHTS & BIASES
# ==============================
weights = [load_mif_bin(f"./mif_files/edge_encoder_w_1_{i}.mif") for i in range(32)]
biases  = [load_mif_bin(f"./mif_files/edge_encoder_b_1_{i}.mif")[0] for i in range(32)]
gamma   = load_mif_bin("./mif_files/ln_gamma_1.mif")

print(weights[1][:10])  # print first 10 weights of first neuron
print(biases[:10])      # print first 10 biases
print(gamma[:10])       # print first 10 gamma values
NUM_NEURONS = len(weights)
NUM_FEATURES = len(weights[0])

# ==============================
# GENERATE INPUT (Q3.4)
# ==============================
np.random.seed(0)
inputs_float = np.array([      2.04251758 , -1.06883281, 0.62836456,1.43868727, 3.01265113, 0.68338905 ], dtype=float)  # example input
inputs_fixed = [to_fixed(x, 4, 8) for x in inputs_float]

print("Inputs (float):", inputs_float)
print("Inputs (fixed Q3.4):", inputs_fixed)

# ==============================
# FORWARD PASS (FC LAYER)
# ==============================
outputs = []
for n in range(NUM_NEURONS):
    acc = 0
    for i in range(NUM_FEATURES):
        w = weights[n][i]     # Q1.6
        x = inputs_fixed[i]   # Q3.4
        # multiply Q3.4 * Q1.6 = Q4.10
        acc += w * x
    acc += biases[n]  # bias also Q1.6, simple addition
    outputs.append(acc)

print("\nRaw neuron outputs (accumulator units):", outputs)

# ==============================
# RMS NORM
# ==============================
outputs_float = np.array(outputs, dtype=float) / (1<<10)  # convert Q4.10 → float

mean_sq = np.mean(outputs_float ** 2)
eps = 1e-5
rms = np.sqrt(mean_sq + eps)

# gamma scaling (assume Q0.6)
gamma_float = [to_float(g, 6, 8) for g in gamma]

norm_outputs = []
for i in range(NUM_NEURONS):
    print (f"Neuron {i}: output={outputs_float[i]:.6f}, gamma={gamma_float[i]:.6f}")
    y = (outputs_float[i] / rms) * gamma_float[i]
    norm_outputs.append(y)

print("\nRMS:", rms)
for i in norm_outputs:
    print(f"Norm output (float): {i:.6f}, fixed Q0.6: {to_fixed(i, 4, 8)}")
