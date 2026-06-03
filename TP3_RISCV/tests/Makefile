SIM ?= icarus
TOPLEVEL_LANG ?= verilog

SRC_DIR = ../src

TOPLEVEL = RISCV_Top

MODULE = tb_cpu

VERILOG_SOURCES += $(SRC_DIR)/RISCV_Top.v
VERILOG_SOURCES += $(SRC_DIR)/IF_Stage.v
VERILOG_SOURCES += $(SRC_DIR)/IF_ID_Reg.v
VERILOG_SOURCES += $(SRC_DIR)/ID_Stage.v
VERILOG_SOURCES += $(SRC_DIR)/ID_EX_Reg.v
VERILOG_SOURCES += $(SRC_DIR)/EX_Stage.v
VERILOG_SOURCES += $(SRC_DIR)/EX_MEM_Reg.v
VERILOG_SOURCES += $(SRC_DIR)/MEM_Stage.v
VERILOG_SOURCES += $(SRC_DIR)/MEM_WB_Reg.v
VERILOG_SOURCES += $(SRC_DIR)/WB_Stage.v
VERILOG_SOURCES += $(SRC_DIR)/ALU.v
VERILOG_SOURCES += $(SRC_DIR)/Forwarding_Unit.v
VERILOG_SOURCES += $(SRC_DIR)/Hazard_Unit.v
VERILOG_SOURCES += $(SRC_DIR)/halt_detection_unit.v

VERILOG_SOURCES += $(SRC_DIR)/blk_mem_gen_0.v

include $(shell cocotb-config --makefiles)/Makefile.sim