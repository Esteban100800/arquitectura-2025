"""
Codificador / Decodificador de instrucciones RV32I
Basado en el procesador implementado en ID_Stage.v / ALU.v
"""
REG_NAMES = [f"x{i}" for i in range(32)]

def reg(n):
    return REG_NAMES[n & 0x1F]

def sign_extend(value, bits):
    sign_bit = 1 << (bits - 1)
    return (value & (sign_bit - 1)) - (value & sign_bit)

#campos de instruccion
def _fields(instr):
    return {
        "opcode": instr & 0x7F,
        "rd":    (instr >> 7)  & 0x1F,
        "funct3":(instr >> 12) & 0x07,
        "rs1":   (instr >> 15) & 0x1F,
        "rs2":   (instr >> 20) & 0x1F,
        "funct7":(instr >> 25) & 0x7F,
    }

def _imm_i(instr):
    return sign_extend(instr >> 20, 12)

def _imm_s(instr):
    raw = ((instr >> 25) << 5) | ((instr >> 7) & 0x1F)
    return sign_extend(raw, 12)

def _imm_b(instr):
    b12  = (instr >> 31) & 1
    b11  = (instr >> 7)  & 1
    b10_5= (instr >> 25) & 0x3F
    b4_1 = (instr >> 8)  & 0xF
    raw  = (b12 << 12) | (b11 << 11) | (b10_5 << 5) | (b4_1 << 1)
    return sign_extend(raw, 13)

def _imm_u(instr):
    return instr & 0xFFFFF000   # ya en posicion, sin extension de signo

def _imm_j(instr):
    b20    = (instr >> 31) & 1
    b10_1  = (instr >> 21) & 0x3FF
    b11    = (instr >> 20) & 1
    b19_12 = (instr >> 12) & 0xFF
    raw    = (b20 << 20) | (b19_12 << 12) | (b11 << 11) | (b10_1 << 1)
    return sign_extend(raw, 21)


_R_INSTR = {
    (0b000, 0b0000000): "ADD",
    (0b000, 0b0100000): "SUB",
    (0b001, 0b0000000): "SLL",
    (0b010, 0b0000000): "SLT",
    (0b011, 0b0000000): "SLTU",
    (0b100, 0b0000000): "XOR",
    (0b101, 0b0000000): "SRL",
    (0b101, 0b0100000): "SRA",
    (0b110, 0b0000000): "OR",
    (0b111, 0b0000000): "AND",
}

_I_ALU_INSTR = {
    0b000: "ADDI",
    0b010: "SLTI",
    0b011: "SLTIU",
    0b100: "XORI",
    0b110: "ORI",
    0b111: "ANDI",
}

_LOAD_INSTR = {
    0b000: "LB",
    0b001: "LH",
    0b010: "LW",
    0b100: "LBU",
    0b101: "LHU",
}

_STORE_INSTR = {
    0b000: "SB",
    0b001: "SH",
    0b010: "SW",
}

_BRANCH_INSTR = {
    0b000: "BEQ",
    0b001: "BNE",
    0b100: "BLT",
    0b101: "BGE",
    0b110: "BLTU",
    0b111: "BGEU",
}

def decode(instr, pc=None):
    """
    Decodifica una instruccion de 32 bits y devuelve un stringa de ensamblador.
    Si se proporciona pc (int), los branches/saltos muestran la direccion destino.
    """
    f = _fields(instr)
    op = f["opcode"]

    if instr == 0x00000013:
        return "NOP"
    if instr == 0x0000007F:
        return "HALT"

    # R-type
    if op == 0b0110011:
        key = (f["funct3"], f["funct7"])
        mnem = _R_INSTR.get(key, f"R?f3={f['funct3']:03b}f7={f['funct7']:07b}")
        return f"{mnem} {reg(f['rd'])}, {reg(f['rs1'])}, {reg(f['rs2'])}"

    # I-type ALU
    if op == 0b0010011:
        imm = _imm_i(instr)
        f3  = f["funct3"]
        f7  = f["funct7"]
        if f3 == 0b001:                        # SLLI
            return f"SLLI {reg(f['rd'])}, {reg(f['rs1'])}, {f['rs2']}"
        if f3 == 0b101:                        # SRLI / SRAI
            mnem = "SRAI" if f7 & 0x20 else "SRLI"
            return f"{mnem} {reg(f['rd'])}, {reg(f['rs1'])}, {f['rs2']}"
        mnem = _I_ALU_INSTR.get(f3, "I?")
        return f"{mnem} {reg(f['rd'])}, {reg(f['rs1'])}, {imm}"

    # Load
    if op == 0b0000011:
        imm  = _imm_i(instr)
        mnem = _LOAD_INSTR.get(f["funct3"], "LOAD?")
        return f"{mnem} {reg(f['rd'])}, {imm}({reg(f['rs1'])})"

    # Store
    if op == 0b0100011:
        imm  = _imm_s(instr)
        mnem = _STORE_INSTR.get(f["funct3"], "STORE?")
        return f"{mnem} {reg(f['rs2'])}, {imm}({reg(f['rs1'])})"

    # Branch
    if op == 0b1100011:
        imm  = _imm_b(instr)
        mnem = _BRANCH_INSTR.get(f["funct3"], "BR?")
        target = f" -> 0x{(pc + imm) & 0xFFFFFFFF:08X}" if pc is not None else f" ({imm:+d})"
        return f"{mnem} {reg(f['rs1'])}, {reg(f['rs2'])},{target}"

    # JAL
    if op == 0b1101111:
        imm = _imm_j(instr)
        target = f" -> 0x{(pc + imm) & 0xFFFFFFFF:08X}" if pc is not None else f" ({imm:+d})"
        return f"JAL {reg(f['rd'])},{target}"

    # JALR
    if op == 0b1100111:
        imm = _imm_i(instr)
        return f"JALR {reg(f['rd'])}, {reg(f['rs1'])}, {imm}"

    # LUI
    if op == 0b0110111:
        imm = _imm_u(instr)
        return f"LUI {reg(f['rd'])}, 0x{imm >> 12:05X}"

    # AUIPC
    if op == 0b0010111:
        imm = _imm_u(instr)
        target = f" -> 0x{(pc + imm) & 0xFFFFFFFF:08X}" if pc is not None else ""
        return f"AUIPC {reg(f['rd'])}, 0x{imm >> 12:05X}{target}"

    return f"UNKNOWN 0x{instr:08X}"



def _r(opcode, rd, funct3, rs1, rs2, funct7):
    return ((funct7 & 0x7F) << 25 | (rs2 & 0x1F) << 20 |
            (rs1 & 0x1F) << 15 | (funct3 & 0x7) << 12 |
            (rd  & 0x1F) << 7  | (opcode & 0x7F))

def _i(opcode, rd, funct3, rs1, imm):
    return ((imm & 0xFFF) << 20 | (rs1 & 0x1F) << 15 |
            (funct3 & 0x7) << 12 | (rd & 0x1F) << 7 | (opcode & 0x7F))

def _s(rs1, rs2, funct3, imm):
    imm &= 0xFFF
    return ((imm >> 5) << 25 | (rs2 & 0x1F) << 20 | (rs1 & 0x1F) << 15 |
            (funct3 & 0x7) << 12 | (imm & 0x1F) << 7 | 0b0100011)

def _b(rs1, rs2, funct3, imm):
    imm &= 0x1FFE  # solo bits[12:1]
    b12  = (imm >> 12) & 1
    b11  = (imm >> 11) & 1
    b10_5= (imm >> 5)  & 0x3F
    b4_1 = (imm >> 1)  & 0xF
    return (b12 << 31 | b10_5 << 25 | (rs2 & 0x1F) << 20 |
            (rs1 & 0x1F) << 15 | (funct3 & 0x7) << 12 |
            b4_1 << 8 | b11 << 7 | 0b1100011)

def _u(opcode, rd, imm):
    return ((imm & 0xFFFFF000) | (rd & 0x1F) << 7 | (opcode & 0x7F))

def _j(rd, imm):
    imm &= 0x1FFFFE  # bits[20:1]
    b20    = (imm >> 20) & 1
    b10_1  = (imm >> 1)  & 0x3FF
    b11    = (imm >> 11) & 1
    b19_12 = (imm >> 12) & 0xFF
    return (b20 << 31 | b19_12 << 12 | b11 << 11 |
            b10_1 << 21 | (rd & 0x1F) << 7 | 0b1101111)


def ADD (rd, rs1, rs2): return _r(0b0110011, rd, 0b000, rs1, rs2, 0b0000000)
def SUB (rd, rs1, rs2): return _r(0b0110011, rd, 0b000, rs1, rs2, 0b0100000)
def SLL (rd, rs1, rs2): return _r(0b0110011, rd, 0b001, rs1, rs2, 0b0000000)
def SLT (rd, rs1, rs2): return _r(0b0110011, rd, 0b010, rs1, rs2, 0b0000000)
def SLTU(rd, rs1, rs2): return _r(0b0110011, rd, 0b011, rs1, rs2, 0b0000000)
def XOR (rd, rs1, rs2): return _r(0b0110011, rd, 0b100, rs1, rs2, 0b0000000)
def SRL (rd, rs1, rs2): return _r(0b0110011, rd, 0b101, rs1, rs2, 0b0000000)
def SRA (rd, rs1, rs2): return _r(0b0110011, rd, 0b101, rs1, rs2, 0b0100000)
def OR  (rd, rs1, rs2): return _r(0b0110011, rd, 0b110, rs1, rs2, 0b0000000)
def AND (rd, rs1, rs2): return _r(0b0110011, rd, 0b111, rs1, rs2, 0b0000000)


def ADDI (rd, rs1, imm): return _i(0b0010011, rd, 0b000, rs1, imm)
def SLTI (rd, rs1, imm): return _i(0b0010011, rd, 0b010, rs1, imm)
def SLTIU(rd, rs1, imm): return _i(0b0010011, rd, 0b011, rs1, imm)
def XORI (rd, rs1, imm): return _i(0b0010011, rd, 0b100, rs1, imm)
def ORI  (rd, rs1, imm): return _i(0b0010011, rd, 0b110, rs1, imm)
def ANDI (rd, rs1, imm): return _i(0b0010011, rd, 0b111, rs1, imm)
def SLLI (rd, rs1, shamt): return _r(0b0010011, rd, 0b001, rs1, shamt & 0x1F, 0b0000000)
def SRLI (rd, rs1, shamt): return _r(0b0010011, rd, 0b101, rs1, shamt & 0x1F, 0b0000000)
def SRAI (rd, rs1, shamt): return _r(0b0010011, rd, 0b101, rs1, shamt & 0x1F, 0b0100000)
def NOP():  return ADDI(0, 0, 0)
def HALT(): return 0x0000007F     # opcode=1111111, detectado por halt_detection_unit


def LB (rd, rs1, imm): return _i(0b0000011, rd, 0b000, rs1, imm)
def LH (rd, rs1, imm): return _i(0b0000011, rd, 0b001, rs1, imm)
def LW (rd, rs1, imm): return _i(0b0000011, rd, 0b010, rs1, imm)
def LBU(rd, rs1, imm): return _i(0b0000011, rd, 0b100, rs1, imm)
def LHU(rd, rs1, imm): return _i(0b0000011, rd, 0b101, rs1, imm)

def SB(rs1, rs2, imm): return _s(rs1, rs2, 0b000, imm)
def SH(rs1, rs2, imm): return _s(rs1, rs2, 0b001, imm)
def SW(rs1, rs2, imm): return _s(rs1, rs2, 0b010, imm)


def BEQ (rs1, rs2, imm): return _b(rs1, rs2, 0b000, imm)
def BNE (rs1, rs2, imm): return _b(rs1, rs2, 0b001, imm)
def BLT (rs1, rs2, imm): return _b(rs1, rs2, 0b100, imm)
def BGE (rs1, rs2, imm): return _b(rs1, rs2, 0b101, imm)
def BLTU(rs1, rs2, imm): return _b(rs1, rs2, 0b110, imm)
def BGEU(rs1, rs2, imm): return _b(rs1, rs2, 0b111, imm)


def JAL (rd, imm):       return _j(rd, imm)
def JALR(rd, rs1, imm):  return _i(0b1100111, rd, 0b000, rs1, imm)

def LUI  (rd, imm): return _u(0b0110111, rd, imm << 12)
def AUIPC(rd, imm): return _u(0b0010111, rd, imm << 12)


def disasm(program, base_pc=0):
    """
    Desensambla una lista de enteros de 32 bits.
    program: list[int] o bytes
    Devuelve una lista de strings.
    """
    if isinstance(program, (bytes, bytearray)):
        import struct
        program = list(struct.unpack(f"<{len(program)//4}I", program))

    lines = []
    for i, instr in enumerate(program):
        pc = base_pc + i * 4
        lines.append(f"0x{pc:08X}:  {instr:08X}  {decode(instr, pc)}")
    return lines

def to_bytes(program):
    """Convierte lista de instrucciones (int) a bytes little-endian."""
    import struct
    return b"".join(struct.pack("<I", instr & 0xFFFFFFFF) for instr in program)

def from_hex(hex_str):
    """Parsea una cadena hex (con o sin 0x, separada por espacios/comas/newlines)."""
    import re
    tokens = re.findall(r"[0-9a-fA-F]{8}", hex_str.replace("0x", "").replace("0X", ""))
    return [int(t, 16) for t in tokens]



if __name__ == "__main__":
    # Registros por numero: x0-x31
    program = [
        ADDI(5, 0, 10),     # x5 = 10
        ADDI(6, 0, 3),      # x6 = 3
        ADD (10, 5, 6),     # x10 = x5 + x6 = 13
        SUB (11, 5, 6),     # x11 = x5 - x6 = 7
        AND (5, 10, 11),    # x5 = 13 & 7 = 5
        OR  (6, 10, 11),    # x6 = 13 | 7 = 15
        XOR (10, 5, 6),     # x10 = 5 ^ 15 = 10
        SLL (11, 5, 6),     # x11 = x5 << x6
        SW  (2, 5, 0),      # mem[x2+0] = x5
        LW  (10, 2, 0),     # x10 = mem[x2+0]
        BEQ (5, 6, -8),     # si x5==x6 saltar 2 instrucciones atras
        JAL (1, 12),        # x1 = PC+4, saltar a PC+12
        LUI (5, 0xDEAD),    # x5 = 0xDEAD0000
        AUIPC(6, 0x1),      # x6 = PC + 0x1000
        NOP(),
        JALR(0, 1, 0),      # saltar a x1 (ret)
    ]

    print("=" * 60)
    print("  Programa ensamblado + desensamblado")
    print("=" * 60)
    for line in disasm(program, base_pc=0x00000000):
        print(line)

    print()
    print("Bytes para cargar via UART (hex):")
    raw = to_bytes(program)
    for i in range(0, len(raw), 16):
        chunk = raw[i:i+16]
        print("  " + " ".join(f"{b:02X}" for b in chunk))
