# ubaboot v0.5 atmega32u4 bootloader

ubaboot v0.5 is a USB bootloader for atmega32u4 in 512 bytes.

## Overview

* Targets atmega32u4-based boards
* Compiles to less than 512 bytes
* Tested with [Adafruit Feather 32u4](https://www.adafruit.com/products/2771)
  and [Teensy 2.0](https://www.pjrc.com/store/teensy.html)
* Can write and read (verify) both flash and eeprom memory
* Also reads signature/lock/fuse bytes
* Sample [pyusb](https://walac.github.io/pyusb/) driver program included
* Works with Linux; other platforms may work but not tested

ubaboot uses a custom (vendor-defined) USB protocol. See below for details.

The included `ubaboot.py` driver program can upload and verify firmware.

## Getting started

You must configure ubaboot to work with your board. See `config.h`.

1. Install dependencies:
    * avr-gcc
    * avr-libc
    * make
    * avrdude
    * pyusb
2. Edit `config.h` to set required and optional configuration.
3. Build via `make`.
4. Set your fuses for a 512 byte bootloader.
5. Program your board via "make program". This uses `avrdude` to flash the
    firmware; set `AVRDUDE_PROGRAMMER` in the `Makefile` for your programmer.
6. Install a [udev
    rule](https://github.com/libusb/libusb/wiki/FAQ#can-i-run-libusb-applications-on-linux-without-root-privilege)
    so you can use your device without root privilege.
7. Use `ubaboot.py` to load programs via the bootloader.

### Configuration overview

Required configuration:

* Set crystal/oscillator frequency for your board.
* Set low-speed mode if using the internal RC oscillator.
* Enable USB voltage regulator if needed for your board.

Optional configuration:

* Setup registers and pin number for blinky USB activity LED.
* Customize vendor and product ID.

## Integration with Arduino/Teensyduino

Since Ubaboot is designed for the same processor that the Teensy 2.0 boards have, it is possible to use the Teensyduino
environment to program boards with Ubaboot. Unfortunately, that requires a manual step: to check where the `.hex`file
has been stored and manually launch the `ubaboot.py` program.

To solve this, `ubaboot.py` supports the `--gui` parameter, which waits until a board with ubaboot active is available
in your system, showing a window while it is not available.

To integrate it into your Arduino/Teensyduino IDE, just:

1. open in your favourite editor the `hardware/teensy/avr/platform.txt` file
2. go to the `Post build` section
3. comment all the `recipe.hooks.postbuild` entries
4. add the entry `recipe.hooks.postbuild.1.pattern="{teensytools.path}/ubaboot.py" --gui write "{build.path}/{build.project_name}.hex"`
5. copy `ubaboot.py` into `hardware/tools`

and your Arduino IDE will be ready to work with `ubaboot`. You will only need to choose a `teensy 2.0` board.

## Protocol details

All operations are control transfers type vendor and recipient device.

### Read Signature

Returns the three device signature bytes.

SETUP field | Value
----------- | -----
bmRequestType | 0xc0
bRequest | 1
wValue | ignored
wIndex | ignored
wLength | 3

### Read Flash

Reads program flash memory.

SETUP field | Value
----------- | -----
bmRequestType | 0xc0
bRequest | 2
wValue | address to read
wIndex | ignored
wLength | length to read

Address and length need not be aligned to flash pages.

### Write Flash

Writes program memory.

SETUP field | Value
----------- | -----
bmRequestType | 0x40
bRequest | 3
wValue | address to write
wIndex | ignored
wLength | length to write

Both address and length must be aligned to page boundary (128 bytes for
atmega32u4).

Allow 20 ms timeout per page being programmed.

### Reboot

Reboots into the target program.

SETUP field | Value
----------- | -----
bmRequestType | 0x40
bRequest | 4
wValue | ignored
wIndex | ignored
wLength | 0

### Read EEPROM

Reads EEPROM memory.

SETUP field | Value
----------- | -----
bmRequestType | 0xc0
bRequest | 5
wValue | address to read
wIndex | ignored
wLength | length to read

### Write EEPROM

Writes EEPROM memory.

SETUP field | Value
----------- | -----
bmRequestType | 0x40
bRequest | 6
wValue | address to write
wIndex | ignored
wLength | length to write

Allow 10 ms timeout per byte being programmed.

### Read Fuse/Lock Bytes

Reads the fuse bytes and lock byte.

SETUP field | Value
----------- | -----
bmRequestType | 0xc0
bRequest | 7
wValue | ignored
wIndex | ignored
wLength | 4

The bytes are returned in the following order:

Offset | Value
------ | -----
0 | low fuse
1 | lock byte
2 | extended fuse
3 | high fuse

## Notes

The firmware allows max 64 kib transfers but your USB stack might not.

libusb on linux is limited to 4 kib per control transfer.

USB vendor/product ID 1d50:611c is assigned to ubaboot by
[openmoko](https://raw.githubusercontent.com/openmoko/openmoko-usb-oui/master/usb_product_ids.psv)
and configured by default. You can use this ID in your projects, or customize
if desired.

## Thanks

Thank you Richard Woodbury for reviewing lots of code and testing!

## Copyright notice

Copyright 2017 by Robert Evans (rrevans@gmail.com)

ubaboot is licensed under the terms of
[GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html). See LICENSE for details.

This documentation is licensed under the terms of [CC BY-SA
4.0](https://creativecommons.org/licenses/by-sa/4.0/)
