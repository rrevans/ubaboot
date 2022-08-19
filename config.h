// Copyright 2017 by Robert Evans (rrevans@gmail.com)
//
// This file is part of ubaboot.
//
// ubaboot is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// ubaboot is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with ubaboot.  If not, see <http://www.gnu.org/licenses/>.


// This file contains configuration options for ubaboot.
// Modify these to change the configuration to match your hardware.
//
// Required configuration:
//   1. Choose OSC_MHZ_8 or OSC_MHZ_16 depending on your oscillator
//      (not your system clock)
//   2. Determine whether or not you need the USB regulator enabled
//      and set USB_REGULATOR if so. See the datasheet.
//
// Optional configuration:
//   1. For a blinky activity LED, set USE_LED and configure the pin via
//      LED_DDR_REG   data direction register
//      LED_PORT_REG  port register
//      LED_IONUM     bit number within DDR/PORT registers
//   2. Set USB low speed mode e.g. if using an RC oscillator.
//   3. Customize USB vendor ID and product ID


// USB ID 1d50:611c is assigned to ubaboot by openmoko.
// You can change the USB vendor id and product id if desired.
// These should be written as C literals.
#define VENDOR_ID 0x1d50
#define PRODUCT_ID 0x611c

// Choose which oscillator you are using:
//
//   OSC_MHZ_8     8 MHz crystal, ext. clock, or int. RC oscillator
//   OSC_MHZ_16    16 MHz crystal or external clock
//
// Note: This not the same thing as the system clock frequency and is
//       irrespective of the setting of the CKDIV8 fuse bit.
//
// Note: If you are using the RC oscillator, you must use low-speed mode.
//       See the datasheet for details. To select this mode set OSC_MHZ_8 and
//       uncomment USB_LOW_SPEED below.
//#define OSC_MHZ_8
//#define OSC_MHZ_16

// If you want to use USB low speed mode, uncomment the following line.
// This is required for the RC oscillator.
//#define USB_LOW_SPEED

// If you need the on-chip USB voltage regulator, uncomment the following line.
//#define USB_REGULATOR

// If you would like a status LED, uncomment this line. Also uncomment the
// appropriate lines for DDRLED, PORTLED, and LEDPIN below.
//#define USE_LED
//#define LED_DDR_REG    DDRx
//#define LED_PORT_REG   PORTx
//#define LED_IONUM      n

// Sample configurations follow.
// Note: You must still set VENDOR_ID and PRODUCT_ID above.

// Adafruit Feather 32u4 Basic Proto
//#define OSC_MHZ_8
//#define USE_LED
//#define LED_DDR_REG    DDRC
//#define LED_PORT_REG   PORTC
//#define LED_IONUM      7

// Teensy 2.0
//#define OSC_MHZ_16
//#define USB_REGULATOR
//#define USE_LED
//#define LED_DDR_REG    DDRD
//#define LED_PORT_REG   PORTD
//#define LED_IONUM      6
