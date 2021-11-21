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

# initial values

# Fixed point parameters
FRAC_LEN = 10
BIT_LEN = 16

# normally it is 1,023e6. But the sampling freq is also having e6 factor, e6's are eliminated for simplicity
# also the value is multiplied by 1000 for avoiding floation division
codeFreq = 1023000
carrFreq = 14500000
samplingFreq = 53
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

three_bin = fixed_point.float2bin(3.0,FRAC_LEN,BIT_LEN)

# Initializing I_E, Q_E, I_L, Q_L, I_P, Q_P
I_E_bin = fixed_point.float2bin(0.0,FRAC_LEN,BIT_LEN)
Q_E_bin = fixed_point.float2bin(0.0,FRAC_LEN,BIT_LEN)
I_L_bin = fixed_point.float2bin(0.0,FRAC_LEN,BIT_LEN)
Q_L_bin = fixed_point.float2bin(0.0,FRAC_LEN,BIT_LEN)
I_P_bin = fixed_point.float2bin(0.0,FRAC_LEN,BIT_LEN)
Q_P_bin = fixed_point.float2bin(0.0,FRAC_LEN,BIT_LEN)

# for k in caCode:
#     print(k)
# ----------------------------------------------------------------------------------------


for now do tracking only for one channel
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

        carrCos_bin = fixed_point.float2bin(carrCos,FRAC_LEN,BIT_LEN)
        carrSin_bin = fixed_point.float2bin(carrSin,FRAC_LEN,BIT_LEN)
        
        #least significant 2-bit of raw signal byte
        raw = int.from_bytes(raw_file.read(1),"big") & 3
        if raw == 0 :
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
            qBasebandSignal_bin = fixed_point.mul_float(carrCos_bin,three_bin,FRAC_LEN,FRAC_LEN,BIT_LEN)
            qBasebandSignal_bin = fixed_point.mul_float(carrSin_bin,three_bin,FRAC_LEN,FRAC_LEN,BIT_LEN)
        
        if rawSignal == -3:
            qBasebandSignal_bin = fixed_point.twosComplement(qBasebandSignal_bin)
            iBasebandSignal_bin = fixed_point.twosComplement(iBasebandSignal_bin)

        

        # % Now get early, late, and prompt values for each
        # I_E = sum(earlyCode  .* iBasebandSignal)
        # Q_E = sum(earlyCode  .* qBasebandSignal)
        # I_P = sum(promptCode .* iBasebandSignal)
        # Q_P = sum(promptCode .* qBasebandSignal)
        # I_L = sum(lateCode   .* iBasebandSignal)  
        # Q_L = sum(lateCode   .* qBasebandSignal)

        if e_code == 1:
            I_E_bin = fixed_point.add_float(I_E_bin,iBasebandSignal_bin,FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
            Q_E_bin = fixed_point.add_float(Q_E_bin,qBasebandSignal_bin,FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
        else:
            I_E_bin = fixed_point.add_float(I_E_bin,fixed_point.twosComplement(iBasebandSignal_bin),FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
            Q_E_bin = fixed_point.add_float(Q_E_bin,fixed_point.twosComplement(qBasebandSignal_bin),FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)

        if l_code == 1:
            I_L_bin = fixed_point.add_float(I_L_bin,iBasebandSignal_bin,FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
            Q_L_bin = fixed_point.add_float(Q_L_bin,qBasebandSignal_bin,FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
        else:
            I_L_bin = fixed_point.add_float(I_L_bin,fixed_point.twosComplement(iBasebandSignal_bin),FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
            Q_L_bin = fixed_point.add_float(Q_L_bin,fixed_point.twosComplement(qBasebandSignal_bin),FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
        
        if p_code == 1:
            I_P_bin = fixed_point.add_float(I_P_bin,iBasebandSignal_bin,FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
            Q_P_bin = fixed_point.add_float(Q_P_bin,qBasebandSignal_bin,FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
        else:
            I_P_bin = fixed_point.add_float(I_P_bin,fixed_point.twosComplement(iBasebandSignal_bin),FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)
            Q_P_bin = fixed_point.add_float(Q_P_bin,fixed_point.twosComplement(qBasebandSignal_bin),FRAC_LEN,2*FRAC_LEN,2*BIT_LEN)