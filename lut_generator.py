#!/usr/bin/env python3
"""
gen_inv_sqrt_lut_geo_practical.py
Generates inv_sqrt_lut.mem using geometric series for practical σ² range
"""

import numpy as np

# -----------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------
LUT_SIZE = 20              # number of entries
INT_BITS = 5
FRAC_BITS = 11             # Q5.11 format
Q_SCALE  = 2**FRAC_BITS
MAX_VAL  = 2**(INT_BITS + FRAC_BITS) - 1  # 16-bit max for Q5.11

# Practical variance range
VAR_MIN = 0.01
VAR_MAX = 1024.0

# -----------------------------------------------------------------------
# Compute geometric ratio
# -----------------------------------------------------------------------
r = (VAR_MAX / VAR_MIN)**(1/(LUT_SIZE-1))
a = VAR_MIN

# -----------------------------------------------------------------------
# Output path
# -----------------------------------------------------------------------
FILENAME = "inv_sqrt_lut.mem"
OUT_PATH = FILENAME

# -----------------------------------------------------------------------
# Generate LUT values
# -----------------------------------------------------------------------
entries = []
for i in range(LUT_SIZE):
    var_val = a * (r ** i)
    inv_sq  = 1.0 / np.sqrt(var_val)
    q_val   = int(round(inv_sq * Q_SCALE))
    q_val   = max(0, min(q_val, MAX_VAL))
    entries.append(q_val)

# -----------------------------------------------------------------------
# Write LUT — binary format
# -----------------------------------------------------------------------
with open(OUT_PATH, 'w') as f:
    for val in entries:
        f.write(f"{val:016b}\n")

# -----------------------------------------------------------------------
# Print first 10 entries for verification
# -----------------------------------------------------------------------
print(f"Written {LUT_SIZE} entries to: {OUT_PATH}\n")
print("First 10 entries (decimal for verification):")
for i in range(min(10, LUT_SIZE)):
    var_val  = a * (r ** i)
    expected = 1.0 / np.sqrt(var_val)
    print(f"[{i:2d}] var={var_val:8.3f}  bin={entries[i]:016b}  dec={entries[i]:5d}  Q5.11={entries[i]/Q_SCALE:.6f}  ref_float={expected:.6f}")