def fixed32_to_decimal(bin_str, frac_bits=10):
    """
    Convert a 32-bit signed binary string with fractional bits to decimal.
    
    Parameters:
        bin_str: str, 32-bit binary string e.g. '11111111111111110010000000000000'
        frac_bits: int, number of fractional bits from the right (default 15)
    
    Returns:
        float: decimal value
    """
    # assert len(bin_str) == 32, "Input must be 32-bit binary"
    if len(bin_str) != 32:
        bin_str = bin_str.zfill(32) 
    
    # Convert binary string to integer
    int_val = int(bin_str, 2)
    
    # Handle two's complement for signed numbers
    if bin_str[0] == '1':  # negative number
        int_val -= 2**32
    
    # Apply fractional scaling
    decimal_val = int_val / (2 ** frac_bits)
    
    return decimal_val

# Example usage
binary_numbers = [
    # '00000000000000011111110011000011' 
    # '00000000001100111100010110100000'
    '01100000'    
]

for b in binary_numbers:
    dec = fixed32_to_decimal(b)
    print(f"{b} -> {dec:.6f}")


    