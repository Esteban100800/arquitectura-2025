"""
Testbench cocotb para la ALU del TP, manejada a traves de top_module.
Un test por operacion soportada para que el scoreboard quede claro.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CLK_PERIOD_NS = 10
DATA_WIDTH = 8
DATA_MASK = (1 << DATA_WIDTH) - 1  # 0xFF

# Codigos de operacion definidos en la ALU
OP_ADD = 0b100000
OP_SUB = 0b100010
OP_AND = 0b100100
OP_OR  = 0b100101
OP_XOR = 0b101000
OP_SLL = 0b000010
OP_SRL = 0b000011
OP_NOR = 0b100111


async def reset_and_start(dut):
    """Levanta el reloj, mantiene reset un par de ciclos y lo libera."""
    dut.i_sw.value = 0
    dut.i_btn.value = 0
    dut.i_reset.value = 1
    cocotb.start_soon(Clock(dut.i_clk, CLK_PERIOD_NS, units="ns").start())
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    dut.i_reset.value = 0
    await RisingEdge(dut.i_clk)


async def load_inputs(dut, a, b, op):
    """Carga A (btn[0]), B (btn[1]) y opcode (btn[2]) desde los switches."""
    # Cargar A con btn[0]
    dut.i_sw.value = a & DATA_MASK
    dut.i_btn.value = 0b001
    await RisingEdge(dut.i_clk)
    dut.i_btn.value = 0b000
    await RisingEdge(dut.i_clk)

    # Cargar B con btn[1]
    dut.i_sw.value = b & DATA_MASK
    dut.i_btn.value = 0b010
    await RisingEdge(dut.i_clk)
    dut.i_btn.value = 0b000
    await RisingEdge(dut.i_clk)

    # Cargar opcode con btn[2]
    dut.i_sw.value = op & 0x3F
    dut.i_btn.value = 0b100
    await RisingEdge(dut.i_clk)
    dut.i_btn.value = 0b000
    await RisingEdge(dut.i_clk)


@cocotb.test()
async def test_suma(dut):
    """Verifica la operacion SUMA y el flag de Carry."""
    await reset_and_start(dut)
    a, b = 200, 100  # 300, fuerza overflow para chequear Carry
    await load_inputs(dut, a, b, OP_ADD)

    full = a + b
    expected = full & DATA_MASK
    expected_carry = (full >> DATA_WIDTH) & 1
    result = int(dut.o_Result.value)
    carry = int(dut.o_Carry.value)

    dut._log.info(f"SUMA: {a} + {b} -> Result={result} (esperado {expected}), Carry={carry}")
    assert result == expected, f"Resultado de SUMA incorrecto: {result} != {expected}"
    assert carry == expected_carry, f"Carry de SUMA incorrecto: {carry} != {expected_carry}"


@cocotb.test()
async def test_resta(dut):
    """Verifica la operacion RESTA."""
    await reset_and_start(dut)
    a, b = 90, 30
    await load_inputs(dut, a, b, OP_SUB)

    expected = (a - b) & DATA_MASK
    result = int(dut.o_Result.value)
    carry = int(dut.o_Carry.value)

    dut._log.info(f"RESTA: {a} - {b} -> Result={result} (esperado {expected}), Carry={carry}")
    assert result == expected, f"Resultado de RESTA incorrecto: {result} != {expected}"
    # Como A >= B no deberia haber borrow
    assert carry == 0, f"No deberia activarse el borrow: Carry={carry}"


@cocotb.test()
async def test_and(dut):
    """Verifica la operacion AND bit a bit."""
    await reset_and_start(dut)
    a, b = 0b11001100, 0b10101010
    await load_inputs(dut, a, b, OP_AND)

    expected = a & b
    result = int(dut.o_Result.value)

    dut._log.info(f"AND: {a:08b} & {b:08b} = {result:08b} (esperado {expected:08b})")
    assert result == expected, f"Resultado de AND incorrecto: {result} != {expected}"


@cocotb.test()
async def test_or(dut):
    """Verifica la operacion OR bit a bit."""
    await reset_and_start(dut)
    a, b = 0b11000000, 0b00001111
    await load_inputs(dut, a, b, OP_OR)

    expected = a | b
    result = int(dut.o_Result.value)

    dut._log.info(f"OR: {a:08b} | {b:08b} = {result:08b} (esperado {expected:08b})")
    assert result == expected, f"Resultado de OR incorrecto: {result} != {expected}"


@cocotb.test()
async def test_xor(dut):
    """Verifica la operacion XOR bit a bit."""
    await reset_and_start(dut)
    a, b = 0b11110000, 0b10101010
    await load_inputs(dut, a, b, OP_XOR)

    expected = a ^ b
    result = int(dut.o_Result.value)

    dut._log.info(f"XOR: {a:08b} ^ {b:08b} = {result:08b} (esperado {expected:08b})")
    assert result == expected, f"Resultado de XOR incorrecto: {result} != {expected}"


@cocotb.test()
async def test_shift_left(dut):
    """Verifica el desplazamiento de A a la izquierda en 1 posicion."""
    await reset_and_start(dut)
    a, b = 0b00010101, 0  # B no se usa en esta operacion
    await load_inputs(dut, a, b, OP_SLL)

    expected = (a << 1) & DATA_MASK
    result = int(dut.o_Result.value)

    dut._log.info(f"SHIFT LEFT: {a:08b} << 1 = {result:08b} (esperado {expected:08b})")
    assert result == expected, f"Resultado de SLL incorrecto: {result} != {expected}"


@cocotb.test()
async def test_shift_right(dut):
    """Verifica el desplazamiento de A a la derecha en 1 posicion."""
    await reset_and_start(dut)
    a, b = 0b10101010, 0  # B no se usa en esta operacion
    await load_inputs(dut, a, b, OP_SRL)

    expected = (a >> 1) & DATA_MASK
    result = int(dut.o_Result.value)

    dut._log.info(f"SHIFT RIGHT: {a:08b} >> 1 = {result:08b} (esperado {expected:08b})")
    assert result == expected, f"Resultado de SRL incorrecto: {result} != {expected}"


@cocotb.test()
async def test_nor(dut):
    """Verifica la operacion NOR bit a bit y el flag Zero."""
    await reset_and_start(dut)
    # Eligiendo operandos que dan resultado 0 para verificar el flag Zero
    a, b = 0b11111111, 0b00000000
    await load_inputs(dut, a, b, OP_NOR)

    expected = (~(a | b)) & DATA_MASK
    expected_zero = 1 if expected == 0 else 0
    result = int(dut.o_Result.value)
    zero = int(dut.o_Zero.value)

    dut._log.info(f"NOR: ~({a:08b} | {b:08b}) = {result:08b} (esperado {expected:08b}), Zero={zero}")
    assert result == expected, f"Resultado de NOR incorrecto: {result} != {expected}"
    assert zero == expected_zero, f"Flag Zero incorrecto: {zero} != {expected_zero}"