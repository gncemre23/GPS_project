from os import ftruncate
import fixed_point
import math

# a = 257.000234
# b = 4.0123452

# y= fixed_point.float2bin(a,20,32)
# print(y)

# z= fixed_point.float2bin(b,20,32)
# print(z)

# t = fixed_point.mul_float(y,z,20,20,32)
# print(t)

# x = fixed_point.bin2float(t,20)
# print("fixed point mul:", x)

# print("real mult", a*b)


# z = fixed_point.twosComplement('0011')
# print(z)
# a = fixed_point.bin2float(z,2)
# print(a)

# c = fixed_point.float2bin(-256.75,20,32)
# print(c)

# d= fixed_point.float2bin(512.80,20,32)
# e=fixed_point.add_float(c,d,20,20,32)
# print(e)
# f=fixed_point.bin2float(e,20)
# print(f)

# num = 1250
# print(fixed_point.int2fixedPoint(num,1000,10,16))

# initial values

# Fixed point parameters
FRAC_LEN = 10
BIT_LEN = 16

# tau coefficients
# FIX: fix this constant
tau_carr_coef = 264.864

tau_code_coef = 5.297 * 1000

oldCarrErr = 0
oldCarrNco = 0
oldCodeErr = 0
oldCodeNco = 0



# normally it is 1,023e6. But the sampling freq is also having e6 factor, e6's are eliminated for simplicity
# also the value is multiplied by 1000 for avoiding floation division
codeFreq = 1023000
carrFreq = 14500000
samplingFreq = 53


# DDS parameters for 32-bit phase input
# 0.023 = 100 * 10 ^ 6 / 2 ^ 32
freq_res = 0.023 * 1000
phase_inc = carrFreq * 1000 // freq_res

#remcodePhase = fixed_point.float2bin(0.0,20,32)
remcodePhase = 0
# -0.5
earlyLateSpc_n = fixed_point.float2bin(-0.5, 20, 32)
# 0.5
earlyLateSpc_p = fixed_point.float2bin(0.5, 20, 32)

PRN = 8
caCode = [0] * 1025

raw_file = open("NTLab_first40ms.bin", "rb")

# ---- reading file to caCode and generating the array with corresponding early late promp approach
# caCode [caCode[1024] caCode caCode[0] ]

text_file = open("PRN.txt", "r")
i = 0
while i < (PRN-1)*1023:
    text_file.readline()
    i += 1
str = text_file.readline()
print(str)
if int(text_file.readline()[0]) == 1:
    caCode[1024] = -1
else:
    caCode[1024] = 1

for i in range(0, 1023):
    if int(text_file.readline()[0]) == 1:
        caCode[i+1] = -1
    else:
        caCode[i+1] = 1
if int(text_file.readline()[0]) == 1:
    caCode[0] = -1
else:
    caCode[0] = 1

three_bin = fixed_point.float2bin(3.0, FRAC_LEN, BIT_LEN)

# Initializing I_E, Q_E, I_L, Q_L, I_P, Q_P
I_E_bin = fixed_point.float2bin(0.0, FRAC_LEN, BIT_LEN)
Q_E_bin = fixed_point.float2bin(0.0, FRAC_LEN, BIT_LEN)
I_L_bin = fixed_point.float2bin(0.0, FRAC_LEN, BIT_LEN)
Q_L_bin = fixed_point.float2bin(0.0, FRAC_LEN, BIT_LEN)
I_P_bin = fixed_point.float2bin(0.0, FRAC_LEN, BIT_LEN)
Q_P_bin = fixed_point.float2bin(0.0, FRAC_LEN, BIT_LEN)

# for k in caCode:
#     print(k)
# ----------------------------------------------------------------------------------------


# for now do tracking only for one channel
for ms in range(0, 36):
    #codePhaseStep = codeFreq / settings.samplingFreq;
    # integer division
    codePhaseStep = codeFreq // samplingFreq
    for blk in range(0, 53000):
        # early Code gen
        # tcode = fixed_point.add_float(remcodePhase,earlyLateSpc_n,20,20,32)
        # blk_bin = fixed_point.float2bin(blk,20,32)
        # inc = fixed_point.mul_float(codePhaseStep,blk_bin,20,20,32)
        # tcode =  fixed_point.add_float(tcode,inc,20,20,32)
        tcode = codePhaseStep*blk-500
        if tcode < 0:
            tcode = 0
        else:
            # ceil(tcode/1000)
            tcode = (tcode + 999) // 1000
        e_code = caCode[tcode]

        # late Code gen
        tcode = codePhaseStep*blk+500
        if tcode < 0:
            tcode = 0
        else:
            # ceil(tcode/1000)
            tcode = (tcode + 999) // 1000
        l_code = caCode[tcode]

        # prompt Code gen
        tcode = codePhaseStep*blk
        if tcode < 0:
            tcode = 0
        else:
            # ceil(tcode/1000)
            tcode = (tcode + 999) // 1000
        p_code = caCode[tcode]

        # %% Generate the carrier frequency to mix the signal to baseband -----------
        #     time    = (0:blksize) ./ settings.samplingFreq;

        #     % Get the argument to sin/cos functions
        #     trigarg = ((carrFreq * 2.0 * pi) .* time) + remCarrPhase;
        #     remCarrPhase = rem(trigarg(blksize+1), (2 * pi));

        #     % Finally compute the signal to mix the collected data to bandband
        #     carrCos = cos(trigarg(1:blksize));
        #     carrSin = sin(trigarg(1:blksize));

        # ignore remCarrPhase and remCodePhase
        triarg = carrFreq * 2.0 * math.pi * blk/(samplingFreq * (10**6))
        carrCos = math.cos(triarg)
        carrSin = math.cos(triarg)

        carrCos_bin = fixed_point.float2bin(carrCos, FRAC_LEN, BIT_LEN)
        carrSin_bin = fixed_point.float2bin(carrSin, FRAC_LEN, BIT_LEN)

        # least significant 2-bit of raw signal byte
        raw = int.from_bytes(raw_file.read(1), "big") & 3
        if raw == 0:
            rawSignal = 1
        elif raw == 1:
            rawSignal = -1
        elif raw == 2:
            rawSignal = 3
        else:
            rawSignal = -3

        # qBasebandSignal = carrCos * rawSignal
        # iBasebandSignal = carrSin * rawSignal

        if rawSignal == 1:
            qBasebandSignal_bin = carrCos_bin
            iBasebandSignal_bin = carrSin_bin
        elif rawSignal == -1:
            qBasebandSignal_bin = fixed_point.twosComplement(carrCos_bin)
            iBasebandSignal_bin = fixed_point.twosComplement(carrSin_bin)
        else:
            qBasebandSignal_bin = fixed_point.mul_float(
                carrCos_bin, three_bin, FRAC_LEN, FRAC_LEN, BIT_LEN)
            qBasebandSignal_bin = fixed_point.mul_float(
                carrSin_bin, three_bin, FRAC_LEN, FRAC_LEN, BIT_LEN)

        if rawSignal == -3:
            qBasebandSignal_bin = fixed_point.twosComplement(
                qBasebandSignal_bin)
            iBasebandSignal_bin = fixed_point.twosComplement(
                iBasebandSignal_bin)

        # % Now get early, late, and prompt values for each
        # I_E = sum(earlyCode  .* iBasebandSignal)
        # Q_E = sum(earlyCode  .* qBasebandSignal)
        # I_P = sum(promptCode .* iBasebandSignal)
        # Q_P = sum(promptCode .* qBasebandSignal)
        # I_L = sum(lateCode   .* iBasebandSignal)
        # Q_L = sum(lateCode   .* qBasebandSignal)

        if e_code == 1:
            I_E_bin = fixed_point.add_float(
                I_E_bin, iBasebandSignal_bin, FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)
            Q_E_bin = fixed_point.add_float(
                Q_E_bin, qBasebandSignal_bin, FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)
        else:
            I_E_bin = fixed_point.add_float(I_E_bin, fixed_point.twosComplement(
                iBasebandSignal_bin), FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)
            Q_E_bin = fixed_point.add_float(Q_E_bin, fixed_point.twosComplement(
                qBasebandSignal_bin), FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)

        if l_code == 1:
            I_L_bin = fixed_point.add_float(
                I_L_bin, iBasebandSignal_bin, FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)
            Q_L_bin = fixed_point.add_float(
                Q_L_bin, qBasebandSignal_bin, FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)
        else:
            I_L_bin = fixed_point.add_float(I_L_bin, fixed_point.twosComplement(
                iBasebandSignal_bin), FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)
            Q_L_bin = fixed_point.add_float(Q_L_bin, fixed_point.twosComplement(
                qBasebandSignal_bin), FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)

        if p_code == 1:
            I_P_bin = fixed_point.add_float(
                I_P_bin, iBasebandSignal_bin, FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)
            Q_P_bin = fixed_point.add_float(
                Q_P_bin, qBasebandSignal_bin, FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)
        else:
            I_P_bin = fixed_point.add_float(I_P_bin, fixed_point.twosComplement(
                iBasebandSignal_bin), FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)
            Q_P_bin = fixed_point.add_float(Q_P_bin, fixed_point.twosComplement(
                qBasebandSignal_bin), FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)
    # end of the loop for 1ms

    # ------Implement carrier loop discriminator (phase detector)----
    # carrError = atan(Q_P / I_P) / (2.0 * pi);

    # % Implement carrier loop filter and generate NCO command
    # carrNco = oldCarrNco + (tau2carr/tau1carr) * ...
    #     (carrError - oldCarrError) + carrError * (PDIcarr/tau1carr);
    # oldCarrNco   = carrNco;
    # oldCarrError = carrError;

    # % Modify carrier freq based on NCO command
    # carrFreq = carrFreqBasis + carrNco;

    # trackResults(channelNr).carrFreq(loopCnt) = carrFreq;

    # scaled by 1000
    Q_P_int = fixed_point.bin2float(Q_P_bin, 2*FRAC_LEN) * 1000 * 1000
    I_P_int = fixed_point.bin2float(I_P_bin, 2*FRAC_LEN) * 1000

    # this division result is 1000 times the real division value
    div_Q_P_I_P_int = Q_P_int // I_P_int
    # the division value is converted to fixed point number with 14*bit fractal part
    # since the cordic accepts the input type fix_14_16
    div_Q_P_I_P = fixed_point.int2fixedPoint(div_Q_P_I_P_int, 1000, 14, 16)
    arc_tan = math.atan(div_Q_P_I_P)

    # scale the arc_tan result by 1000000
    arc_tan_int = arc_tan * 1000000
    # scale the 2*pi by 1000
    pi_2_int = math.pi * 2 * 1000

    # integer division giving the result arc_tan/2*pi * 1000
    # which is the 1000 times carrErr having the same level with carrFreq
    carrErr = arc_tan_int // pi_2_int

    # ignore pdi part
    diff = carrErr - oldCarrErr
    diff_bin = fixed_point.float2bin(diff, 2*FRAC_LEN, 2*BIT_LEN)
    tau_coeff_bin = fixed_point.float2bin(tau_carr_coef, 2*FRAC_LEN, 2*BIT_LEN)

    oldCarrErr 

    diff_mult_bin = fixed_point.mul_float(
        diff_bin, tau_coeff_bin, 2*FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)

    oldCarrNco_bin = fixed_point.float2bin(oldCarrNco,2*FRAC_LEN)
    carrNco_bin = fixed_point.add_float(
        oldCarrNco_bin, diff_mult_bin, 2*FRAC_LEN, 2*FRAC_LEN, 2*BIT_LEN)

    carrNco = int(fixed_point.bin2float(carrNco_bin,2*FRAC_LEN))
    
    # DDS phase inc(PINC) input
    phase_inc += carrNco // freq_res
    carrFreq = (phase_inc * freq_res) / 1000.0

    oldCarrNco = carrNco
    oldCarrErr = carrErr
    #     (carrError - oldCarrError) + carrError * (PDIcarr/tau1carr);
    # -----------------------------------------------------------------
    
    # -------- Find DLL error and update code NCO -------------------------------------
    # codeError = (sqrt(I_E * I_E + Q_E * Q_E) - sqrt(I_L * I_L + Q_L * Q_L)) / ...
    #     (sqrt(I_E * I_E + Q_E * Q_E) + sqrt(I_L * I_L + Q_L * Q_L));
    
    # % Implement code loop filter and generate NCO command
    # codeNco = oldCodeNco + (tau2code/tau1code) * ...
    #     (codeError - oldCodeError) + codeError * (PDIcode/tau1code);
    # oldCodeNco   = codeNco;
    # oldCodeError = codeError;
    
    # % Modify code freq based on NCO command
    # codeFreq = settings.codeFreqBasis - codeNco;
    
    # trackResults(channelNr).codeFreq(loopCnt) = codeFreq;
    
    I_E_bin_sqr = fixed_point.mul_float(I_E_bin,I_E_bin,2*FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
    Q_E_bin_sqr = fixed_point.mul_float(Q_E_bin,Q_E_bin,2*FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)

    I_L_bin_sqr = fixed_point.mul_float(I_L_bin,I_L_bin,2*FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
    Q_L_bin_sqr = fixed_point.mul_float(Q_L_bin,Q_L_bin,2*FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)

    I_E_sqr_plus_Q_E_sqr = fixed_point.add_float(I_E_bin_sqr,Q_E_bin_sqr,2*FRAC_LEN, 2*BIT_LEN)
    I_L_sqr_plus_Q_L_sqr = fixed_point.add_float(I_L_bin_sqr,Q_L_bin_sqr,2*FRAC_LEN, 2*BIT_LEN)

    t_bin = fixed_point.float2bin(10000,2*FRAC_LEN,2*BIT_LEN)
    # scale by 10000 for integer sqrt operation
    sqr_int_0 = fixed_point.mul_float(I_E_sqr_plus_Q_E_sqr, t_bin, 2*FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
    sqr_int_1 = fixed_point.mul_float(I_L_sqr_plus_Q_L_sqr, t_bin, 2*FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)

    # Cordic will be used for sqrt 
    # square roots are 100 times the real value because of 10000 scaling factor.
    sqrt_int_0 = math.sqrt(sqr_int_0)
    sqrt_int_1 = math.sqrt(sqr_int_1)

    codeErr = (sqrt_int_0 - sqrt_int_1) * 1000 // (sqrt_int_0 + sqrt_int_1)

    codeNco  = oldCodeNco + ((codeErr - oldCodeErr) * tau_code_coef) // 1000 

    codeFreq -= codeNco
    oldCodeNco = codeNco
    oldCodeErr = codeErr

    # ------------------------------------------------------------------------------