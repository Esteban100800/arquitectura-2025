"""
Testbench cocotb para el procesador RISC-V pipeline (RISCV_Top).

Estrategia: maneja directamente las señales del puerto debug (sin pasar por UART)
para cargar programas, correrlos hasta HALT y verificar registros/memoria.
Cada test es un programa RISC-V completo que ejercita una caracteristica del CPU.

Requiere riscv_instr.py en el mismo directorio (encoder/decoder de instrucciones).
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

from riscv_instr import (
    ADDI, ADD, SUB, AND, OR, XOR, SLL, SRL, SRA,
    SLT, SLTU, ANDI, ORI, XORI, SLTI, SLTIU,
    SLLI, SRLI, SRAI,
    LW, SW, BEQ, BNE, BLT, BGE, BLTU, BGEU,
    JAL, JALR, LUI, AUIPC,
    NOP, HALT,
)

CLK_PERIOD_NS = 20    # 50 MHz, igual que el clock_wiz divide en el diseño real
MAX_CYCLES    = 3000  # limite por programa para evitar simulaciones infinitas


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def init_cpu(dut):
    """Resetea el CPU y lo deja halted listo para cargar un programa."""
    # En cocotb 2.0 las tasks lanzadas con start_soon se cancelan al terminar
    # cada test, asi que arrancamos el clock de cero en cada test sin riesgo
    # de doble driver.
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    # Valores por defecto en las señales debug
    dut.debug_halt.value       = 1
    dut.debug_step.value       = 0
    dut.debug_imem_we.value    = 0
    dut.debug_imem_addr.value  = 0
    dut.debug_imem_wdata.value = 0
    dut.debug_rf_addr.value    = 0
    dut.debug_dmem_addr.value  = 0
    dut.debug_dmem_wdata.value = 0
    dut.debug_dmem_we.value    = 0
    dut.rst.value              = 1

    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 5)


async def load_program(dut, program):
    """Escribe la lista de instrucciones de 32 bits en imem desde la direccion 0."""
    for i, instr in enumerate(program):
        dut.debug_imem_addr.value  = i * 4
        dut.debug_imem_wdata.value = instr & 0xFFFFFFFF
        dut.debug_imem_we.value    = 1
        await RisingEdge(dut.clk)
    dut.debug_imem_we.value = 0
    # Dar unos ciclos para que el ultimo write de BRAM se asiente y para que
    # IF/ID precargue la primera instruccion antes de soltar el halt
    await ClockCycles(dut.clk, 5)


async def run_until_halt(dut, max_cycles=MAX_CYCLES):
    """Libera el halt y espera hasta que halt_done_out=1. Retorna ciclos transcurridos."""
    dut.debug_halt.value = 0
    for cycles in range(max_cycles):
        await RisingEdge(dut.clk)
        # int() sobre un valor X tira ValueError en cocotb 2.0 -> lo tratamos como "todavia no"
        try:
            halt = int(dut.halt_done_out.value)
        except ValueError:
            halt = 0
        if halt == 1:
            await ClockCycles(dut.clk, 2)   # margen para que se asiente todo
            return cycles + 1
    raise TimeoutError(f"El programa no alcanzo HALT en {max_cycles} ciclos")


async def read_reg(dut, n):
    """Lee xN por el puerto debug del banco de registros (lectura combinacional)."""
    dut.debug_rf_addr.value = n
    await ClockCycles(dut.clk, 1)
    return int(dut.debug_rf_rdata.value)


async def read_mem(dut, byte_addr):
    """Lee dmem en una direccion byte (debe ser word-aligned)."""
    dut.debug_dmem_addr.value = byte_addr
    await ClockCycles(dut.clk, 1)
    return int(dut.debug_dmem_rdata.value)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_basic_arithmetic(dut):
    """ADDI / ADD / SUB - sanity check de la aritmetica."""
    await init_cpu(dut)
    program = [
        ADDI(1, 0, 25),    # x1 = 25
        ADDI(2, 0, 17),    # x2 = 17
        ADD (3, 1, 2),     # x3 = x1 + x2 = 42
        SUB (4, 1, 2),     # x4 = x1 - x2 = 8
        HALT(),
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x3 = await read_reg(dut, 3)
    x4 = await read_reg(dut, 4)
    dut._log.info(f"Aritmetica basica ({cycles} ciclos): x3={x3}, x4={x4}")
    assert x3 == 42, f"x3 esperado 42, obtuvo {x3}"
    assert x4 == 8,  f"x4 esperado 8, obtuvo {x4}"


@cocotb.test()
async def test_logical_ops(dut):
    """AND / OR / XOR sobre patrones de bits conocidos."""
    await init_cpu(dut)
    program = [
        ADDI(1, 0, 0xF0),   # x1 = 0xF0
        ADDI(2, 0, 0x0F),   # x2 = 0x0F
        AND (3, 1, 2),       # x3 = 0xF0 & 0x0F = 0x00
        OR  (4, 1, 2),       # x4 = 0xF0 | 0x0F = 0xFF
        XOR (5, 1, 2),       # x5 = 0xF0 ^ 0x0F = 0xFF
        HALT(),
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x3 = await read_reg(dut, 3)
    x4 = await read_reg(dut, 4)
    x5 = await read_reg(dut, 5)
    dut._log.info(f"Logicas ({cycles} ciclos): x3=0x{x3:02X}, x4=0x{x4:02X}, x5=0x{x5:02X}")
    assert x3 == 0x00
    assert x4 == 0xFF
    assert x5 == 0xFF


@cocotb.test()
async def test_forwarding(dut):
    """Instrucciones con dependencias consecutivas: ejercita EX/MEM y MEM/WB forwarding."""
    await init_cpu(dut)
    # Cada instruccion depende de la anterior sin nops intermedios.
    # Sin forwarding correcto, los valores leeran datos viejos del regfile.
    program = [
        ADDI(1, 0, 10),    # x1 = 10
        ADDI(2, 1, 5),     # x2 = x1 + 5 = 15    (fwd EX/MEM de x1)
        ADD (3, 1, 2),     # x3 = x1 + x2 = 25   (fwd MEM/WB de x1, EX/MEM de x2)
        SUB (4, 3, 1),     # x4 = x3 - x1 = 15   (fwd EX/MEM de x3, MEM/WB de x1)
        HALT(),
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x1 = await read_reg(dut, 1)
    x2 = await read_reg(dut, 2)
    x3 = await read_reg(dut, 3)
    x4 = await read_reg(dut, 4)
    dut._log.info(f"Forwarding ({cycles} ciclos): x1={x1}, x2={x2}, x3={x3}, x4={x4}")
    assert (x1, x2, x3, x4) == (10, 15, 25, 15)


@cocotb.test()
async def test_load_use_stall(dut):
    """LW seguido inmediatamente por uso del dato cargado -> requiere stall de 1 ciclo."""
    await init_cpu(dut)
    program = [
        ADDI(1, 0, 0x42),    # x1 = 0x42
        SW  (0, 1, 0),       # mem[0] = x1 (0x42)
        LW  (2, 0, 0),       # x2 = mem[0]
        ADD (3, 2, 2),       # x3 = x2 + x2  <- usa x2 que viene del LW
        HALT(),
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x2 = await read_reg(dut, 2)
    x3 = await read_reg(dut, 3)
    dut._log.info(f"Load-use stall ({cycles} ciclos): x2=0x{x2:X}, x3=0x{x3:X}")
    assert x2 == 0x42, f"x2 esperado 0x42, obtuvo 0x{x2:X}"
    assert x3 == 0x84, f"x3 esperado 0x84, obtuvo 0x{x3:X}"


@cocotb.test()
async def test_branch_taken(dut):
    """BLT tomado hacia adelante: salta sobre la instruccion siguiente."""
    await init_cpu(dut)
    # Si el branch se toma, x3 queda en su valor centinela (7).
    # Si NO se toma (bug), x3 se sobreescribe con 99.
    program = [
        ADDI(3, 0, 7),       # PC=0 : x3 = 7 (centinela)
        ADDI(1, 0, 5),       # PC=4 : x1 = 5
        ADDI(2, 0, 10),      # PC=8 : x2 = 10
        BLT (1, 2, 8),       # PC=12: 5<10 => taken, salta a PC+8=20
        ADDI(3, 0, 99),      # PC=16: deberia saltarse
        HALT(),              # PC=20: destino
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x3 = await read_reg(dut, 3)
    dut._log.info(f"Branch taken ({cycles} ciclos): x3={x3}")
    assert x3 == 7, f"x3 esperado 7 (centinela intacto), obtuvo {x3}"


@cocotb.test()
async def test_branch_not_taken(dut):
    """BEQ no tomado: la instruccion siguiente al branch se ejecuta normalmente."""
    await init_cpu(dut)
    program = [
        ADDI(1, 0, 5),       # x1 = 5
        ADDI(2, 0, 7),       # x2 = 7
        ADDI(3, 0, 0),       # x3 = 0
        BEQ (1, 2, 8),       # 5 != 7 => NO se toma, sigue derecho
        ADDI(3, 0, 42),      # se ejecuta porque el branch no se tomo
        HALT(),
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x3 = await read_reg(dut, 3)
    dut._log.info(f"Branch not taken ({cycles} ciclos): x3={x3}")
    assert x3 == 42, f"x3 esperado 42, obtuvo {x3}"


@cocotb.test()
async def test_jal_jalr(dut):
    """JAL + JALR estilo llamada y retorno de subrutina."""
    await init_cpu(dut)
    # main:
    #   x1 = 0          (resultado)
    #   x2 = 5          (parametro)
    #   jal x10, sub    (x10 = return addr = PC+4, salta a sub)
    #   halt            (al volver)
    # sub: calcula x1 = x2 * 3 con sumas
    #   x1 = x2
    #   x1 += x2
    #   x1 += x2
    #   jalr x0, x10, 0 (retorna usando x10)
    program = [
        # main
        ADDI(1, 0, 0),       # PC=0 : x1 = 0
        ADDI(2, 0, 5),       # PC=4 : x2 = 5
        JAL (10, 12),        # PC=8 : x10 = PC+4 = 12, salta a PC+12 = 20
        HALT(),              # PC=12: destino del retorno
        NOP(),               # PC=16: padding
        # sub (en PC=20)
        ADD (1, 0, 2),       # PC=20: x1 = x2 = 5
        ADD (1, 1, 2),       # PC=24: x1 += x2 = 10
        ADD (1, 1, 2),       # PC=28: x1 += x2 = 15
        JALR(0, 10, 0),      # PC=32: PC = x10 (retorna a PC=12, el HALT)
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x1 = await read_reg(dut, 1)
    x10 = await read_reg(dut, 10)
    dut._log.info(f"JAL/JALR ({cycles} ciclos): x1={x1}, x10=0x{x10:X}")
    assert x1 == 15, f"x1 esperado 15 (5*3), obtuvo {x1}"
    assert x10 == 12, f"x10 (return addr) esperado 12, obtuvo {x10}"


@cocotb.test()
async def test_sum_loop(dut):
    """Bucle: suma 1+2+...+10 = 55."""
    await init_cpu(dut)
    # x1 = acumulador, x2 = i, x3 = limite (11)
    # loop:  if i == limite goto end
    #        acc += i
    #        i += 1
    #        goto loop
    # end:   halt
    program = [
        ADDI(1, 0, 0),       # PC=0 : acc = 0
        ADDI(2, 0, 1),       # PC=4 : i   = 1
        ADDI(3, 0, 11),      # PC=8 : lim = 11
        BEQ (2, 3, 16),      # PC=12: if i==lim => salta a PC+16 = 28 (HALT)
        ADD (1, 1, 2),       # PC=16: acc += i
        ADDI(2, 2, 1),       # PC=20: i += 1
        JAL (0, -12),        # PC=24: salta atras a PC-12 = 12 (BEQ)
        HALT(),              # PC=28
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x1 = await read_reg(dut, 1)
    dut._log.info(f"Suma 1..10 ({cycles} ciclos): x1={x1}")
    assert x1 == 55, f"Suma esperada 55, obtuvo {x1}"


@cocotb.test()
async def test_fibonacci(dut):
    """Fibonacci iterativo: fib(10) = 55."""
    await init_cpu(dut)
    # x1 = n (contador, decrementa hasta 0)
    # x2 = a = fib(actual)
    # x3 = b = fib(siguiente)
    # x4 = tmp
    # loop:  if n == 0 goto end
    #        tmp = a + b
    #        a   = b
    #        b   = tmp
    #        n  -= 1
    #        goto loop
    # end:   halt
    program = [
        ADDI(1, 0, 10),      # PC=0 : n = 10
        ADDI(2, 0, 0),       # PC=4 : a = 0
        ADDI(3, 0, 1),       # PC=8 : b = 1
        BEQ (1, 0, 24),      # PC=12: if n==0 => salta a PC+24 = 36 (HALT)
        ADD (4, 2, 3),       # PC=16: tmp = a + b
        ADD (2, 0, 3),       # PC=20: a = b
        ADD (3, 0, 4),       # PC=24: b = tmp
        ADDI(1, 1, -1),      # PC=28: n -= 1
        JAL (0, -20),        # PC=32: salta atras a PC-20 = 12 (BEQ)
        HALT(),              # PC=36
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    a = await read_reg(dut, 2)
    n = await read_reg(dut, 1)
    dut._log.info(f"Fibonacci(10) ({cycles} ciclos): a=x2={a}, n=x1={n}")
    assert a == 55, f"fib(10) esperado 55, obtuvo {a}"
    assert n == 0,  f"Contador deberia haber llegado a 0, obtuvo {n}"


@cocotb.test()
async def test_memory_array(dut):
    """SW de un array de 5 elementos, luego LW y suma. Resultado esperado: 150."""
    await init_cpu(dut)
    # Almacena [10, 20, 30, 40, 50] en mem[0,4,8,12,16] y los suma en x10.
    program = [
        # Cargar valores en registros temporales
        ADDI(1, 0, 10),      # x1 = 10
        ADDI(2, 0, 20),      # x2 = 20
        ADDI(3, 0, 30),      # x3 = 30
        ADDI(4, 0, 40),      # x4 = 40
        ADDI(5, 0, 50),      # x5 = 50
        # Escribir en memoria (offset desde x0=0)
        SW  (0, 1, 0),       # mem[0]  = 10
        SW  (0, 2, 4),       # mem[4]  = 20
        SW  (0, 3, 8),       # mem[8]  = 30
        SW  (0, 4, 12),      # mem[12] = 40
        SW  (0, 5, 16),      # mem[16] = 50
        # Sumar leyendo de memoria
        ADDI(10, 0, 0),      # x10 = 0 (acumulador)
        LW  (11, 0, 0),      # x11 = mem[0]
        ADD (10, 10, 11),    # acc += x11
        LW  (11, 0, 4),
        ADD (10, 10, 11),
        LW  (11, 0, 8),
        ADD (10, 10, 11),
        LW  (11, 0, 12),
        ADD (10, 10, 11),
        LW  (11, 0, 16),
        ADD (10, 10, 11),
        HALT(),
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x10 = await read_reg(dut, 10)
    mem_0 = await read_mem(dut, 0)
    mem_16 = await read_mem(dut, 16)
    dut._log.info(f"Suma array ({cycles} ciclos): x10={x10}, mem[0]={mem_0}, mem[16]={mem_16}")
    assert x10 == 150,  f"Suma esperada 150, obtuvo {x10}"
    assert mem_0 == 10, f"mem[0] esperado 10, obtuvo {mem_0}"
    assert mem_16 == 50, f"mem[16] esperado 50, obtuvo {mem_16}"


@cocotb.test()
async def test_shifts(dut):
    """Shifts logicos y aritmeticos: SLL, SRL, SRA + variantes inmediatas (SLLI, SRAI)."""
    await init_cpu(dut)
    program = [
        ADDI(1, 0, 0x10),    # x1 = 16 = 0b10000
        ADDI(2, 0, 2),       # x2 = 2 (cantidad de shift)
        SLL (3, 1, 2),       # x3 = 0x10 << 2 = 0x40
        SRL (4, 1, 2),       # x4 = 0x10 >> 2 = 0x04
        ADDI(5, 0, -16),     # x5 = -16 = 0xFFFFFFF0
        SRA (6, 5, 2),       # x6 = -16 >>>2 = -4 = 0xFFFFFFFC  (arith: propaga signo)
        SRL (7, 5, 2),       # x7 = 0xFFFFFFF0 >> 2 = 0x3FFFFFFC (logico: rellena 0)
        SLLI(8, 1, 4),       # x8 = 0x10 << 4 = 0x100
        SRAI(9, 5, 4),       # x9 = -16 >>>4 = -1 = 0xFFFFFFFF
        HALT(),
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x3 = await read_reg(dut, 3)
    x4 = await read_reg(dut, 4)
    x6 = await read_reg(dut, 6)
    x7 = await read_reg(dut, 7)
    x8 = await read_reg(dut, 8)
    x9 = await read_reg(dut, 9)
    dut._log.info(f"Shifts ({cycles} ciclos): x3=0x{x3:X}, x4=0x{x4:X}, "
                  f"x6=0x{x6:X}, x7=0x{x7:X}, x8=0x{x8:X}, x9=0x{x9:X}")
    assert x3 == 0x40,       f"SLL: esperado 0x40, obtuvo 0x{x3:X}"
    assert x4 == 0x04,       f"SRL: esperado 0x04, obtuvo 0x{x4:X}"
    assert x6 == 0xFFFFFFFC, f"SRA negativo: esperado 0xFFFFFFFC, obtuvo 0x{x6:X}"
    assert x7 == 0x3FFFFFFC, f"SRL de negativo: esperado 0x3FFFFFFC, obtuvo 0x{x7:X}"
    assert x8 == 0x100,      f"SLLI: esperado 0x100, obtuvo 0x{x8:X}"
    assert x9 == 0xFFFFFFFF, f"SRAI -1: esperado 0xFFFFFFFF, obtuvo 0x{x9:X}"


@cocotb.test()
async def test_immediates(dut):
    """Inmediatos: ADDI con valores negativos (sign extension) y ANDI/ORI/XORI."""
    await init_cpu(dut)
    program = [
        ADDI(1, 0, -1),       # x1 = -1 = 0xFFFFFFFF (sign-extension del 0xFFF de 12 bits)
        ADDI(2, 0, -2048),    # x2 = -2048 (limite minimo del inmediato signed de 12 bits)
        ADDI(3, 0, 2047),     # x3 = +2047 (limite maximo)
        ADDI(4, 0, 0x7F0),    # x4 = 2032 (bit 11 = 0, sin sign extension a negativo)
        ANDI(5, 4, 0x0F0),    # x5 = 0x7F0 & 0x0F0 = 0x0F0
        ORI (6, 4, 0x00F),    # x6 = 0x7F0 | 0x00F = 0x7FF
        XORI(7, 4, 0x055),    # x7 = 0x7F0 ^ 0x055 = 0x7A5
        HALT(),
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x1 = await read_reg(dut, 1)
    x2 = await read_reg(dut, 2)
    x3 = await read_reg(dut, 3)
    x5 = await read_reg(dut, 5)
    x6 = await read_reg(dut, 6)
    x7 = await read_reg(dut, 7)
    dut._log.info(f"Inmediatos ({cycles} ciclos): x1=0x{x1:X}, x2=0x{x2:X}, x3={x3}, "
                  f"x5=0x{x5:X}, x6=0x{x6:X}, x7=0x{x7:X}")
    assert x1 == 0xFFFFFFFF, f"ADDI -1 sign-ext: esperado 0xFFFFFFFF, obtuvo 0x{x1:X}"
    assert x2 == 0xFFFFF800, f"ADDI -2048: esperado 0xFFFFF800, obtuvo 0x{x2:X}"
    assert x3 == 2047,       f"ADDI +2047: esperado 2047, obtuvo {x3}"
    assert x5 == 0x0F0
    assert x6 == 0x7FF
    assert x7 == 0x7A5


@cocotb.test()
async def test_set_less_than(dut):
    """SLT, SLTU, SLTI, SLTIU: generan 1 o 0 segun comparacion (signed / unsigned)."""
    await init_cpu(dut)
    program = [
        ADDI(1, 0, 5),
        ADDI(2, 0, 10),
        SLT  (3, 1, 2),      # x3 = (5 < 10) signed       = 1
        SLT  (4, 2, 1),      # x4 = (10 < 5) signed       = 0
        SLT  (5, 1, 1),      # x5 = (5 < 5)               = 0
        ADDI (6, 0, -1),     # x6 = -1 = 0xFFFFFFFF
        SLT  (7, 6, 1),      # x7 = (-1 < 5) signed       = 1
        SLTU (8, 6, 1),      # x8 = (0xFFFFFFFF <u 5)     = 0 (sin signo es grandote)
        SLTI (9, 1, 10),     # x9 = (5 < 10)              = 1
        SLTI (10, 1, -10),   # x10 = (5 < -10) signed     = 0
        SLTIU(11, 1, 10),    # x11 = (5 <u 10)            = 1
        HALT(),
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    results = {}
    for n in (3, 4, 5, 7, 8, 9, 10, 11):
        results[n] = await read_reg(dut, n)
    dut._log.info(f"Set-less-than ({cycles} ciclos): {results}")
    expected = {3: 1, 4: 0, 5: 0, 7: 1, 8: 0, 9: 1, 10: 0, 11: 1}
    assert results == expected, f"Esperado {expected}, obtuvo {results}"


@cocotb.test()
async def test_lui_auipc(dut):
    """LUI: cargar inmediato en bits[31:12]. AUIPC: PC + (imm << 12) para direccionamiento PC-relative."""
    await init_cpu(dut)
    program = [
        LUI  (1, 0x12345),     # PC=0 : x1 = 0x12345000
        ADDI (1, 1, 0x678),    # PC=4 : x1 = 0x12345000 + 0x678 = 0x12345678
        AUIPC(2, 1),           # PC=8 : x2 = 8 + (1 << 12) = 0x00001008
        AUIPC(3, 0),           # PC=12: x3 = 12 + 0        = 12 (solo PC)
        HALT(),                # PC=16
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x1 = await read_reg(dut, 1)
    x2 = await read_reg(dut, 2)
    x3 = await read_reg(dut, 3)
    dut._log.info(f"LUI/AUIPC ({cycles} ciclos): x1=0x{x1:X}, x2=0x{x2:X}, x3={x3}")
    assert x1 == 0x12345678, f"LUI+ADDI: esperado 0x12345678, obtuvo 0x{x1:X}"
    assert x2 == 0x1008,     f"AUIPC(PC=8, imm=1): esperado 0x1008, obtuvo 0x{x2:X}"
    assert x3 == 12,         f"AUIPC(PC=12, imm=0): esperado 12, obtuvo {x3}"


@cocotb.test()
async def test_all_branches(dut):
    """BNE, BGE, BLTU, BGEU - los branches que no cubren los tests anteriores."""
    await init_cpu(dut)
    # Cada branch debe saltar sobre una instruccion "veneno" que altera un centinela.
    # Si los 4 funcionan, los 4 centinelas quedan intactos en sus valores iniciales.
    program = [
        ADDI(3, 0, 7),         # centinela para BNE
        ADDI(4, 0, 8),         # centinela para BGE
        ADDI(5, 0, 9),         # centinela para BLTU
        ADDI(6, 0, 6),         # centinela para BGEU
        ADDI(1, 0, 5),
        ADDI(2, 0, 10),
        # BNE: 5 != 10 => taken
        BNE (1, 2, 8),
        ADDI(3, 0, 99),        # veneno (no debe ejecutarse)
        # BGE: 10 >= 5 (signed) => taken
        BGE (2, 1, 8),
        ADDI(4, 0, 88),        # veneno
        # BLTU: 5 <u 10 => taken
        BLTU(1, 2, 8),
        ADDI(5, 0, 77),        # veneno
        # BGEU: 0xFFFFFFFF >=u 1 => taken
        ADDI(7, 0, -1),
        ADDI(8, 0, 1),
        BGEU(7, 8, 8),
        ADDI(6, 0, 66),        # veneno
        HALT(),
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x3 = await read_reg(dut, 3)
    x4 = await read_reg(dut, 4)
    x5 = await read_reg(dut, 5)
    x6 = await read_reg(dut, 6)
    dut._log.info(f"Branches BNE/BGE/BLTU/BGEU ({cycles} ciclos): "
                  f"x3={x3}, x4={x4}, x5={x5}, x6={x6}")
    assert (x3, x4, x5, x6) == (7, 8, 9, 6), (
        f"Centinelas alterados: x3={x3} (esp 7), x4={x4} (esp 8), "
        f"x5={x5} (esp 9), x6={x6} (esp 6)"
    )


@cocotb.test()
async def test_zero_register(dut):
    """x0 siempre lee como 0, sin importar lo que se intente escribir."""
    await init_cpu(dut)
    program = [
        ADDI(0, 0, 42),        # intenta x0 = 42 (debe ignorarse)
        ADD (1, 0, 0),         # x1 = x0 + x0 (debe ser 0)
        ADDI(2, 0, 100),       # x2 = 100
        ADD (0, 2, 2),         # intenta x0 = 200 (debe ignorarse)
        ADD (3, 0, 2),         # x3 = x0 + x2 = 0 + 100 = 100
        SUB (4, 2, 0),         # x4 = x2 - x0 = 100
        HALT(),
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x0 = await read_reg(dut, 0)
    x1 = await read_reg(dut, 1)
    x3 = await read_reg(dut, 3)
    x4 = await read_reg(dut, 4)
    dut._log.info(f"x0 zero-register ({cycles} ciclos): x0={x0}, x1={x1}, x3={x3}, x4={x4}")
    assert x0 == 0, f"x0 debe ser siempre 0, leyo {x0}"
    assert x1 == 0, f"x0+x0 deberia ser 0, obtuvo {x1}"
    assert x3 == 100
    assert x4 == 100


@cocotb.test()
async def test_gcd(dut):
    """Algoritmo de Euclides por restas: gcd(48, 36) = 12. Programa con 2 paths y branch backward."""
    await init_cpu(dut)
    # Algoritmo:
    #   loop:  if a == b   goto end
    #          if a <  b   goto sub_b
    #          a -= b
    #          goto loop
    #   sub_b: b -= a
    #          goto loop
    #   end:   halt
    program = [
        ADDI(1, 0, 48),        # PC=0 : a = 48
        ADDI(2, 0, 36),        # PC=4 : b = 36
        BEQ (1, 2, 24),        # PC=8 : if a==b => PC+24 = 32 (HALT)
        BLT (1, 2, 12),        # PC=12: if a<b  => PC+12 = 24 (sub_b)
        SUB (1, 1, 2),         # PC=16: a -= b   (caso a > b)
        JAL (0, -12),          # PC=20: jump a PC-12 = 8 (loop)
        SUB (2, 2, 1),         # PC=24: b -= a   (sub_b)
        JAL (0, -20),          # PC=28: jump a PC-20 = 8 (loop)
        HALT(),                # PC=32
    ]
    await load_program(dut, program)
    cycles = await run_until_halt(dut)

    x1 = await read_reg(dut, 1)
    x2 = await read_reg(dut, 2)
    dut._log.info(f"GCD(48,36) ({cycles} ciclos): a=x1={x1}, b=x2={x2}")
    assert x1 == 12 and x2 == 12, f"GCD esperado 12, obtuvo x1={x1}, x2={x2}"