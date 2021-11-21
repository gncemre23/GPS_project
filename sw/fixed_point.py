import math


def twosComplement(bin_str):
    bit_len = len(bin_str)
    dec = 0
    for i in range(0, len(bin_str)):
        if int(bin_str[i]) == 0:
            factor = 1
        else:
            factor = 0

        dec += (2**(bit_len-i-1)) * factor
    dec += 1
    return bin(dec)[2:].zfill(bit_len)


def bin2float(bin_str, frac_len):
    minus = 1
    if bin_str[0] == '1':
        bin_str = twosComplement(bin_str)
        minus = -1

    int_len = len(bin_str)-frac_len
    int_part = int(bin_str[0:int_len], 2)
    frac_part = 0.0
    for i in range(0, frac_len):
        frac_part += 0.5**(i+1) * int(bin_str[int_len+i])
    return minus*(int_part + frac_part)

# to convert x to a.b . it is assumed that the scaling factor is known
# Example: 1250 is obtained by 1.25 * 1000
# So the scaling factor is 1000. By this function 1.25 is wanted to obtain
# again.
def int2fixedPoint(num, scale, frac_len, bit_len):
    int_part = abs(num) // scale
    frac_part = abs(num) - int_part * scale

    int_str = bin(int_part)[2:].zfill(bit_len - frac_len)
    frac_str = list(bin(0)[2:].zfill(frac_len))
    for i in range(0, frac_len):
        frac_part = frac_part*2
        if(frac_part >= scale):
            frac_str[i] = '1'
            frac_part -= scale
        else:
            frac_str[i] = '0'
    frac_str = ''.join(frac_str)
    out = int_str+frac_str
    if num < 0:
        return twosComplement(int_str+frac_str)
    return int_str+frac_str

def float2bin(num, frac_len, bit_len):
    # todo: remove this if conditon. Instead use abs of num for flooring
    # todo: do the twosComplement at the end.
    if num < 0:
        int_part = abs(math.ceil(num))
        frac_part = -num - int_part
    else:
        int_part = math.floor(num)
        frac_part = num - int_part
    int_str = bin(int_part)[2:].zfill(bit_len - frac_len)
    frac_str = list(bin(0)[2:].zfill(frac_len))
    for i in range(0, frac_len):
        frac_part = frac_part*2
        if(frac_part >= 1.0):
            frac_str[i] = '1'
            frac_part -= 1
        else:
            frac_str[i] = '0'
    frac_str = ''.join(frac_str)
    out = int_str+frac_str
    if num < 0:
        return twosComplement(int_str+frac_str)
    return int_str+frac_str


def mul_float(bin_str1, bin_str2, in_frac_len, out_frac_len, out_bit_len):
    float1 = bin2float(bin_str1, in_frac_len)
    float2 = bin2float(bin_str2, in_frac_len)
    out = float1 * float2
    return float2bin(out, out_frac_len, out_bit_len)


def add_float(bin_str1, bin_str2, in_frac_len, out_frac_len, out_bit_len):
    float1 = bin2float(bin_str1, in_frac_len)
    float2 = bin2float(bin_str2, in_frac_len)
    out = float1 + float2
    return float2bin(out, out_frac_len, out_bit_len)
