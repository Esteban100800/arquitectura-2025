SIM ?= icarus
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES += $(PWD)/../src/top_alu.v
VERILOG_SOURCES += $(PWD)/../src/alu.v

TOPLEVEL = top_alu

# Modulo Python con los tests (sin la extension .py)
MODULE = tb_alu

include $(shell cocotb-config --makefiles)/Makefile.sim