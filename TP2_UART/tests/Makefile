SIM ?= icarus
TOPLEVEL_LANG ?= verilog

SRC_DIR = ../src

VERILOG_SOURCES += $(SRC_DIR)/UART.v
VERILOG_SOURCES += $(SRC_DIR)/baud_rate_generator.v
VERILOG_SOURCES += $(SRC_DIR)/receiver.v
VERILOG_SOURCES += $(SRC_DIR)/transmitter.v

TOPLEVEL = UART

MODULE = tb_uart

# Override de parametros para acelerar la simulacion.
# Con CLOCK_FREQ=100MHz y BAUD_RATE=1MHz queda DIVISOR=6
# => 16 baud_ticks * 6 ciclos = 96 ciclos de clock por bit
# Frame completo de 10 bits ~ 960 ciclos (muy manejable).
COMPILE_ARGS += -PUART.CLOCK_FREQ=100000000
COMPILE_ARGS += -PUART.BAUD_RATE=1000000

include $(shell cocotb-config --makefiles)/Makefile.sim