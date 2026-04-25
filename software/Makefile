# =============================================================================
# Makefile  --  Build firmware for the RISC-V NN SoC
# =============================================================================

CROSS   ?= riscv-none-elf-
CC      := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
SIZE    := $(CROSS)size

ifeq ($(OS),Windows_NT)
    RM    = del /Q /F
    NULL  = NUL
else
    RM    = rm -f
    NULL  = /dev/null
endif

CFLAGS  := -march=rv32i -mabi=ilp32 -mcmodel=medlow \
           -O2 -ffreestanding -nostdlib -nostartfiles -fno-builtin \
           -Wall -Wextra -Wno-unused-parameter \
           -ffunction-sections -fdata-sections

LDFLAGS := -T link.ld -nostdlib -Wl,--gc-sections

OBJS := startup.o main.o uart_driver.o nn_driver.o

.PHONY: all
all: imem.hex firmware.dis
	@echo ""
	@echo "=== Firmware size ==="
	@$(SIZE) firmware.elf
	@echo ""
	@echo "=== Memory-map sanity check ==="
	-@python ../scripts/check_no_collision.py firmware.elf

firmware.elf: $(OBJS) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS)

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary $< $@

imem.hex: firmware.bin
	python ../scripts/bin_to_hex.py $< $@

firmware.dis: firmware.elf
	$(OBJDUMP) -d -M no-aliases $< > $@

%.o: %.c nn_driver.h uart_driver.h
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.S
	$(CC) $(CFLAGS) -c -o $@ $<

.PHONY: clean
ifeq ($(OS),Windows_NT)
clean:
	-$(RM) *.o      2> $(NULL)
	-$(RM) *.elf    2> $(NULL)
	-$(RM) *.bin    2> $(NULL)
	-$(RM) *.hex    2> $(NULL)
	-$(RM) *.dis    2> $(NULL)
else
clean:
	$(RM) *.o *.elf *.bin *.hex *.dis
endif

.PHONY: info
info:
	@echo "CROSS   = $(CROSS)"
	@echo "CC      = $(CC)"
	@echo "CFLAGS  = $(CFLAGS)"
	@echo "LDFLAGS = $(LDFLAGS)"
	@echo "OBJS    = $(OBJS)"
