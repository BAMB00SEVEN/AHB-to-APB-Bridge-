#==============================================================================
# Makefile - AHB-to-APB Bridge simulation (Icarus Verilog + GTKWave)
#==============================================================================

TOP        := tb_ahb_apb_bridge
RTL_DIR    := ../rtl
TB_DIR     := ../tb
SIM_OUT    := $(TOP).vvp
VCD_FILE   := ahb_apb_bridge.vcd

RTL_SRCS   := $(RTL_DIR)/ahb_apb_bridge.v $(RTL_DIR)/apb_slave_mem.v
TB_SRCS    := $(TB_DIR)/tb_ahb_apb_bridge.v

.PHONY: all run wave clean

all: run

$(SIM_OUT): $(RTL_SRCS) $(TB_SRCS)
	iverilog -g2012 -o $(SIM_OUT) $(RTL_SRCS) $(TB_SRCS)

run: $(SIM_OUT)
	vvp $(SIM_OUT)

wave: run
	gtkwave $(VCD_FILE) &

clean:
	rm -f $(SIM_OUT) $(VCD_FILE)
