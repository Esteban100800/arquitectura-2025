"""
Testbench cocotb para el modulo UART (TX + RX juntos).

Para acelerar la simulacion se overridean los parametros desde el Makefile:
  CLOCK_FREQ = 100 MHz, BAUD_RATE = 1 MHz  =>  DIVISOR = 6
  16 baud_ticks/bit * 6 ciclos/tick = 96 ciclos de clock por bit.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_PERIOD_NS = 10
CLOCKS_PER_BIT = 96  # depende de los parametros override del Makefile


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def setup_dut(dut):
    """Inicializa señales, arranca el clock y aplica reset."""
    dut.rx.value = 1        # linea idle en alto
    dut.tx_start.value = 0
    dut.data_in.value = 0
    dut.i_reset.value = 1
    cocotb.start_soon(Clock(dut.i_clk, CLK_PERIOD_NS, units="ns").start())
    await ClockCycles(dut.i_clk, 5)
    dut.i_reset.value = 0
    await ClockCycles(dut.i_clk, 5)


async def drive_uart_frame(dut, byte):
    """Maneja la linea rx con un frame UART completo (start + 8 bits + stop)."""
    # Start bit
    dut.rx.value = 0
    await ClockCycles(dut.i_clk, CLOCKS_PER_BIT)
    # 8 bits de datos, LSB primero
    for i in range(8):
        dut.rx.value = (byte >> i) & 1
        await ClockCycles(dut.i_clk, CLOCKS_PER_BIT)
    # Stop bit
    dut.rx.value = 1
    await ClockCycles(dut.i_clk, CLOCKS_PER_BIT)


async def capture_tx_frame(dut, byte_to_send):
    """Dispara una TX, captura el frame muestreando en el medio de cada bit
    y retorna el byte reconstruido. Tambien asserta start y stop bits."""
    dut.data_in.value = byte_to_send
    dut.tx_start.value = 1
    await RisingEdge(dut.i_clk)
    dut.tx_start.value = 0

    # Esperar el flanco descendente del start bit
    while int(dut.tx.value) == 1:
        await RisingEdge(dut.i_clk)

    # Muestrear en el centro del bit
    await ClockCycles(dut.i_clk, CLOCKS_PER_BIT // 2)
    assert int(dut.tx.value) == 0, "Start bit deberia ser 0"

    received = 0
    for i in range(8):
        await ClockCycles(dut.i_clk, CLOCKS_PER_BIT)
        received |= (int(dut.tx.value) & 1) << i

    await ClockCycles(dut.i_clk, CLOCKS_PER_BIT)
    assert int(dut.tx.value) == 1, "Stop bit deberia ser 1"
    return received


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_idle(dut):
    """Verifica que tx esté en alto y que data_ready no se active sin frame."""
    await setup_dut(dut)
    await ClockCycles(dut.i_clk, 200)
    tx = int(dut.tx.value)
    data_ready = int(dut.data_ready.value)
    dut._log.info(f"IDLE: tx={tx}, data_ready={data_ready}")
    assert tx == 1, "tx deberia estar en alto en idle"
    assert data_ready == 0, "data_ready no deberia activarse sin trama entrante"


@cocotb.test()
async def test_transmit(dut):
    """Envia 0x5A y verifica el frame en tx bit a bit."""
    await setup_dut(dut)
    byte_to_send = 0x5A
    received = await capture_tx_frame(dut, byte_to_send)
    dut._log.info(f"TX: enviado {byte_to_send:#04x}, capturado {received:#04x}")
    assert received == byte_to_send, f"Byte transmitido incorrecto: {received:#04x} != {byte_to_send:#04x}"


@cocotb.test()
async def test_transmit_zero(dut):
    """Edge case: transmite 0x00, todos los bits de datos en 0."""
    await setup_dut(dut)
    byte_to_send = 0x00
    received = await capture_tx_frame(dut, byte_to_send)
    dut._log.info(f"TX 0x00: capturado {received:#04x}")
    assert received == byte_to_send, f"Byte transmitido incorrecto: {received:#04x} != {byte_to_send:#04x}"


@cocotb.test()
async def test_transmit_all_ones(dut):
    """Edge case: transmite 0xFF, todos los bits de datos en 1."""
    await setup_dut(dut)
    byte_to_send = 0xFF
    received = await capture_tx_frame(dut, byte_to_send)
    dut._log.info(f"TX 0xFF: capturado {received:#04x}")
    assert received == byte_to_send, f"Byte transmitido incorrecto: {received:#04x} != {byte_to_send:#04x}"


@cocotb.test()
async def test_receive(dut):
    """Aplica un frame UART completo sobre rx y verifica data_out."""
    await setup_dut(dut)
    byte_to_send = 0xA5

    await drive_uart_frame(dut, byte_to_send)
    await ClockCycles(dut.i_clk, CLOCKS_PER_BIT)

    received = int(dut.data_out.value)
    dut._log.info(f"RX: enviado {byte_to_send:#04x}, recibido {received:#04x}")
    assert received == byte_to_send, f"Byte recibido incorrecto: {received:#04x} != {byte_to_send:#04x}"


@cocotb.test()
async def test_tx_done_pulse(dut):
    """Verifica que tx_done sea un pulso de exactamente 1 ciclo de clock."""
    await setup_dut(dut)

    pulse_count = [0]

    async def count_tx_done():
        while True:
            await RisingEdge(dut.i_clk)
            if int(dut.tx_done.value) == 1:
                pulse_count[0] += 1

    cocotb.start_soon(count_tx_done())

    dut.data_in.value = 0x37
    dut.tx_start.value = 1
    await RisingEdge(dut.i_clk)
    dut.tx_start.value = 0

    # Esperar frame completo + margen
    await ClockCycles(dut.i_clk, 12 * CLOCKS_PER_BIT)

    dut._log.info(f"tx_done estuvo alto {pulse_count[0]} ciclo(s) durante la TX")
    assert pulse_count[0] == 1, f"tx_done deberia pulsar 1 vez, pulso {pulse_count[0]} veces"


@cocotb.test()
async def test_data_ready_pulse(dut):
    """Verifica que data_ready sea un pulso de exactamente 1 ciclo de clock."""
    await setup_dut(dut)

    pulse_count = [0]

    async def count_data_ready():
        while True:
            await RisingEdge(dut.i_clk)
            if int(dut.data_ready.value) == 1:
                pulse_count[0] += 1

    cocotb.start_soon(count_data_ready())

    await drive_uart_frame(dut, 0x77)
    await ClockCycles(dut.i_clk, 2 * CLOCKS_PER_BIT)

    dut._log.info(f"data_ready estuvo alto {pulse_count[0]} ciclo(s) durante la RX")
    assert pulse_count[0] == 1, f"data_ready deberia pulsar 1 vez, pulso {pulse_count[0]} veces"


@cocotb.test()
async def test_rx_noise_filter(dut):
    """Un glitch corto en rx no deberia ser detectado como start bit.
    Despues del glitch, un frame valido sigue siendo recibido correctamente."""
    await setup_dut(dut)

    pulse_count = [0]

    async def monitor_data_ready():
        while True:
            await RisingEdge(dut.i_clk)
            if int(dut.data_ready.value) == 1:
                pulse_count[0] += 1

    cocotb.start_soon(monitor_data_ready())

    # Glitch corto: rx baja por menos de los 8 baud_ticks requeridos
    dut.rx.value = 0
    await ClockCycles(dut.i_clk, CLOCKS_PER_BIT // 4)  # ~4 baud_ticks
    dut.rx.value = 1

    # Esperar varios bit times para confirmar que no se procesa
    await ClockCycles(dut.i_clk, 12 * CLOCKS_PER_BIT)

    dut._log.info(f"Glitch en rx: data_ready se activo {pulse_count[0]} vez/veces")
    assert pulse_count[0] == 0, "El glitch corto no deberia ser detectado como frame"

    # Confirmar que el receiver sigue funcional con un frame valido
    await drive_uart_frame(dut, 0x69)
    await ClockCycles(dut.i_clk, CLOCKS_PER_BIT)

    received = int(dut.data_out.value)
    dut._log.info(f"Post-glitch frame valido: recibido {received:#04x} (esperado 0x69)")
    assert received == 0x69, f"Frame valido post-glitch fallido: {received:#04x} != 0x69"


@cocotb.test()
async def test_loopback(dut):
    """Conecta tx a rx por software y verifica que un byte enviado se recibe correctamente."""
    await setup_dut(dut)
    byte_to_send = 0xC3

    async def loopback():
        while True:
            await RisingEdge(dut.i_clk)
            dut.rx.value = int(dut.tx.value)

    cocotb.start_soon(loopback())
    await ClockCycles(dut.i_clk, 10)

    dut.data_in.value = byte_to_send
    dut.tx_start.value = 1
    await RisingEdge(dut.i_clk)
    dut.tx_start.value = 0

    await ClockCycles(dut.i_clk, 12 * CLOCKS_PER_BIT)

    received = int(dut.data_out.value)
    dut._log.info(f"LOOPBACK: enviado {byte_to_send:#04x}, recibido {received:#04x}")
    assert received == byte_to_send, f"Loopback fallido: {received:#04x} != {byte_to_send:#04x}"


@cocotb.test()
async def test_loopback_multiple(dut):
    """Envia varios bytes consecutivos via loopback y verifica que llegan todos."""
    await setup_dut(dut)

    async def loopback():
        while True:
            await RisingEdge(dut.i_clk)
            dut.rx.value = int(dut.tx.value)

    cocotb.start_soon(loopback())
    await ClockCycles(dut.i_clk, 10)

    bytes_to_send = [0x55, 0xAA, 0x42, 0x91]

    for byte in bytes_to_send:
        dut.data_in.value = byte
        dut.tx_start.value = 1
        await RisingEdge(dut.i_clk)
        dut.tx_start.value = 0

        # Esperar un frame completo + margen antes de mandar el siguiente
        await ClockCycles(dut.i_clk, 12 * CLOCKS_PER_BIT)

        received = int(dut.data_out.value)
        dut._log.info(f"Loopback multi: enviado {byte:#04x}, recibido {received:#04x}")
        assert received == byte, f"Byte {byte:#04x} no llego correcto: recibi {received:#04x}"