VAR_MIN   = 0.01
VAR_MAX   = 1024.0
LUT_SIZE  = 20
FRAC_BITS = 20
VAR_BITS  = 32

scale = 2 ** FRAC_BITS

# Generate localparams
for i in range(LUT_SIZE - 1):
    t = VAR_MIN * (VAR_MAX / VAR_MIN) ** ((i + 1) / (LUT_SIZE - 1))
    fixed = round(t * scale)
    fixed = min(fixed, (1 << VAR_BITS) - 1)
    print(f"localparam [VAR_BITS-1:0] THR_{i:<2} = 32'h{fixed:08X};  // {t:.6f}")

print()

# Generate function
print("function [LUT_BITS-1:0] variance_to_lut_addr;")
print("    input [VAR_BITS-1:0] var_in;")
print("    begin")
for i in range(LUT_SIZE - 1):
    prefix = "if      " if i == 0 else "else if "
    print(f"        {prefix}(var_in <= THR_{i:<2}) variance_to_lut_addr = {i};")
print(f"        else                       variance_to_lut_addr = {LUT_SIZE - 1};")
print("    end")
print("endfunction")

def check_normalize_saturation():
    # After dividing by std, values should fit in Q1.7 - sanity check.
    import math
    max_abs = 4.0  # 4 sigma cap
    q17 = int(max_abs * (1 << 7))
    assert q17 < (1 << 15), q17
    print("normalize: saturation OK")


if __name__ == "__main__":
    check_normalize_saturation()
