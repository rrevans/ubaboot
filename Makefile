# Copyright 2017 by Robert Evans (rrevans@gmail.com)
#
# This file is part of ubaboot.
#
# ubaboot is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubaboot is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubaboot.  If not, see <http://www.gnu.org/licenses/>.

# For best results use a recent version of GNU make.
# Tested with GNU Make 4.1

MCU = atmega32u4
FORMAT = ihex
TARGET = ubaboot
SRCS += $(TARGET).S
SRCS += usbdesc.c
LDMAP = $(TARGET).lds
MAKEFILE = Makefile

AVRDUDE_PROGRAMMER = -c usbtiny -B10
AVRDUDE_FLAGS = -p $(MCU) $(AVRDUDE_PORT) $(AVRDUDE_PROGRAMMER)
AVRDUDE_WRITE_FLASH = -U flash:w:$(TARGET).hex
AVRDUDE_VERIFY_FLASH = -U flash:v:$(TARGET).hex

CFLAGS += -std=gnu11
CFLAGS += -Os -g
CFLAGS += -D_GNU_SOURCE
CFLAGS += -mmcu=$(MCU)
CFLAGS += -Wall -Wextra -Wstrict-prototypes -Werror -Wno-unused-function
CFLAGS += -funsigned-char -funsigned-bitfields -fpack-struct -fshort-enums
CFLAGS += -ffreestanding -nostdlib
LDFLAGS = -Wl,-Map=$(TARGET).map,--cref
LDFLAGS += -T $(LDMAP)

AVR_CC = avr-gcc
AVR_OBJCOPY = avr-objcopy
AVR_OBJDUMP = avr-objdump
AVR_SIZE = avr-size
AVR_NM = avr-nm
AVRDUDE = avrdude

RM = rm -f
MV = mv -f
CP = cp -f
SED = sed

OBJS += $(patsubst %.c,%.o,$(filter %.c,$(SRCS)))
OBJS += $(patsubst %.S,%.o,$(filter %.S,$(SRCS)))
DEPS += $(OBJS:.o=.d)

all: build
build: elf hex lss sym
elf: $(TARGET).elf
hex: $(TARGET).hex
lss: $(TARGET).lss
sym: $(TARGET).sym

$(OBJS): $(MAKEFILE)
elf hex lss sym: $(MAKEFILE)

isptest:
	$(AVRDUDE) $(AVRDUDE_FLAGS)
verify: $(TARGET).hex
	$(AVRDUDE) $(AVRDUDE_FLAGS) $(AVRDUDE_VERIFY_FLASH)
program: build $(TARGET).hex
	$(AVRDUDE) $(AVRDUDE_FLAGS) $(AVRDUDE_WRITE_FLASH)

-include $(DEPS)

.SUFFIXES: .elf .hex .lss .sym

%.hex: %.elf
	$(AVR_OBJCOPY) -O $(FORMAT) -R .eeprom $< $@
%.lss: %.elf
	$(AVR_OBJDUMP) -h -S $< > $@
%.sym: %.elf
	$(AVR_NM) -n $< > $@

$(TARGET).elf: $(OBJS) $(LDMAP) $(MAKEFILE)
	$(AVR_CC) $(CFLAGS) $(OBJS) --output $@ $(LDFLAGS)
	$(AVR_SIZE) $(TARGET).elf

define mkdeps =
$(CP) $*.d $*.d.tmp
$(SED) -e 's/#.*//' -e 's/^[^:]*: *//' -e 's/ *\\$$//' \
	-e '/^$$/ d' -e 's/$$/ :/' < $*.d >> $*.d.tmp
$(MV) $*.d.tmp $*.d
endef

%.o: %.c
	$(AVR_CC) -MD -c $(CFLAGS) $< -o $@
	@$(mkdeps)

%.o: %.S
	$(AVR_CC) -MD -c $(CFLAGS) $< -o $@
	@$(mkdeps)

clean:
	$(RM) $(TARGET).hex $(TARGET).elf \
		$(TARGET).map $(TARGET).sym $(TARGET).lss \
		$(OBJS) $(DEPS)

.PHONY: all build elf hex lss sym clean
