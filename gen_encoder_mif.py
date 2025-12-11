import os
import random

# ==============================
# CONFIG
# ==============================
NUM_FILES = 32   
VALUES_PER_FILE = 32    
BITS = 8                # 8-bit values
NUM_BLOCKS = 8       

OUTPUT_DIR = "./mif_files"

# Create directory if not exists
os.makedirs(OUTPUT_DIR, exist_ok=True)

# ==============================
# GENERATE FILES
# ==============================
for block_idx in range(NUM_BLOCKS):
    for file_idx in range(NUM_FILES):
        filename = os.path.join(OUTPUT_DIR, f"mp_node_w_{block_idx}_3_{file_idx}.mif")
        
        with open(filename, "w") as f:
            for _ in range(VALUES_PER_FILE):
                # Generate signed 8-bit value (-128 to 127)
                val = random.randint(-128, 127)

                # Convert to unsigned 2's complement for writing
                if val < 0:
                    val = (1 << BITS) + val

                # Write as 8-bit binary
                f.write(f"{val:08b}\n")

        print(f"Generated: {filename}")

print("\n✅ All MIF files generated successfully!")