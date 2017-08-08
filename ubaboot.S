; Copyright 2017 by Robert Evans (rrevans@gmail.com)
;
; This file is part of ubaboot.
;
; ubaboot is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; ubaboot is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with ubaboot.  If not, see <http://www.gnu.org/licenses/>.
;
; Configuration:
; NOTE: You must setup config.h before building.
;   USB vendor/product ID
;   Oscillator speed (8 vs 16 MHz)
;   USB low-speed mode (optional)
;   USB voltage regulator (optional)
;   Activity LED (optional)
; See config.h.
;
; Features/commands:
;   Write and read flash memory
;   Write and read eeprom memory
;   Read signature bytes
;   Read lock/fuse bits
;   Reboot into user program
;
; These are implemented as a vendor-defined protocol. See README for details.
; The included sample pyusb driver can upload and verify programs.
;
; Booting disables the watchdog and clears MCUSR which is preserved in r2.
; Jumps directly to user program at $0000 for power-on reset, watchdog reset,
; brownout reset, or USB CPU reset.
;
; User code can enter the bootloader by
;   - disabling interrupts
;   - resetting the USB and PLL registers to reset values
;   - setting SPL, SPH to the top of SRAM
;   - setting MCUSR to zero
;   - jumping to the beginning of the bootloader
;
; Implementation notes:
;   - heavily optimized for size not speed
;   - USB registers accessed via indirect addressing
;   - many branches fall-through instead of jumping
;   - no interrupts (vector table takes too much space)
;   - zero register is moved to r29 vs. gcc's usual r1


#include <avr/io.h>
#include "config.h"
#include "packet.h"

; Y register macros
;
; USB module I/O uses indirect addressing to save program words. The Y register
; is used for this and always points to base of the USB module address space.

; Base address for Y register
#define YBASE       _SFR_MEM_ADDR(UHWCON)

; Offset of I/O register from YBASE
#define YDISP(reg)  (_SFR_MEM_ADDR(reg) - YBASE)


; Zero register
;
; r29 is always zero and is used same way r1 is for C programs. This is done
; because r0:r1 is used for SPM, so it saves program space to move the zero
; register out of the way vs. clearing it after each use. Any register works;
; this reuses the high byte of the Y register because it is zero anyway.

#if (YBASE & 0xff00) != 0
#error YBASE incompatible with ZERO_REG
#endif   // (YBASE & 0xff00) != 0

#define ZERO_REG  r29


; avr-libc 2.0.0 is missing USBRF definition for atmega32u4?
#ifndef USBRF
#define USBRF 5
#endif


; USB standard bmRequestType values
#define WR_STD_DEV   0
#define WR_VEND_DEV  0x40
#define RD_STD_DEV   0x80
#define RD_VEND_DEV  0xc0

; USB standard bRequest values
#define SET_ADDRESS        5
#define GET_DESCRIPTOR     6
#define SET_CONFIGURATION  9

; USB bDescriptorType values
#define DEVICE_DESCRIPTOR  1
#define CONFIG_DESCRIPTOR  2

; USB vendor-defined bRequest values
; These are the core bootloader requests
#define GET_SIGNATURE  1
#define GET_PROGMEM    2
#define SET_PROGMEM    3
#define REBOOT         4
#define GET_EEPROM     5
#define SET_EEPROM     6
#define GET_LOCK       7


; USB commands
;
; The SETUP handling code exploits the fact that for all requests the upper
; four bits of bRequest are zero and the lower four bits of bmRequestType are
; also zero. So the two values can be bit-wise OR'ed and compared at the same
; time against a single command value. This saves space vs. separate compares.
;
; Note that this requires all requests to be DEVICE requests because the lower
; four bits of bmRequestType are used to identify the interface or endpoint for
; other transaction types.
#define CMD_GET_DESC    (RD_STD_DEV | GET_DESCRIPTOR)
#define CMD_SET_ADDR    (WR_STD_DEV | SET_ADDRESS)
#define CMD_SET_CONF    (WR_STD_DEV | SET_CONFIGURATION)
#define CMD_GET_SIGRD   (RD_VEND_DEV | GET_SIGNATURE)
#define CMD_GET_PMEM    (RD_VEND_DEV | GET_PROGMEM)
#define CMD_SET_PMEM    (WR_VEND_DEV | SET_PROGMEM)
#define CMD_REBOOT      (WR_VEND_DEV | REBOOT)
#define CMD_GET_EEPROM  (RD_VEND_DEV | GET_EEPROM)
#define CMD_SET_EEPROM  (WR_VEND_DEV | SET_EEPROM)
#define CMD_GET_LOCK    (RD_VEND_DEV | GET_LOCK)


; USB control endpoint state machine values
;
; Each state reacts to a subset of UEINTX bits.
;
;   State      description and active UEINTX bits
;   -----      ---------------------------
;   SETUP      waiting for SETUP token
;   WR_DATA    waiting for OUT tokens for host-to-device DATA stage
;                 RXOUTI -> handle data from host
;                 NAKINI -> start STATUS stage (new state = WR_STATUS)
;   WR_STATUS  waiting for IN token for host-to-device STATUS data
;                 TXINI  -> transaction done (new state = SETUP)
;   RD_DATA    waiting for IN/OUT token
;                 TXINI  -> buffer DATA stage to send to host
;                           sets state = SETUP when all bytes sent
;
; RXSTPI (not shown above) resets the state machine in all states.
; Other UEINTX bits not listed for a given state are ignored in that state.
;
; The main loop processes UEINTX bits with this equivalent C code:
;
;   uint8_t intx = UEINTX;
;   intx &= state;              // clear all inactive UEINTX bits
;   intx = intx & -intx;        // find lowest asserted UEINTX bit
;   intx = ~intx;               // complement the result for reset
;   uint8_t ms = state & intx;  // selector value (see below)
;   switch (ms) {
;     ...
;     // maybe update intx
;     ...
;   }
;   UEINTX = intx;              // reset handled UEINTX bit(s)
;
; When some active UEINTX bit is asserted, the selector value (ms) equals the
; state value with the lowest asserted UEINTX bit **CLEARED**.
;
; For example, if ms == WR_DATA & ~_BV(RXOUTI) then RXOUTI has been triggered
; in state WR_DATA.
;
; This uniquely identifies both state and each possible asserted UEINTX bit if
; every state value is at least Hamming distance 2 from all other state values.
;
; To meet this criteria some extra bits must be added; any unused bits suffice.
; Below the state values use STALLEDI and FIFOCON for this purpose.
;
; These extra bit values have no effect because the corresponding selector
; values are never tested in the main loop.
;
; RXSTPI is handled separately and does not appear in any of the state values.
;
; The SETUP psuedo-state is zero since no UEINTX bits are active in that state.
; This is always implemented as ZERO_REG.
;
; Summary:
;   WR_DATA   = 01000001b
;   WR_STATUS = 00000011b
;   RD_DATA   = 10000001b
;
; See also ch. 22 of the datasheet.

#define WR_DATA    (_BV(RXOUTI) | _BV(NAKINI))
#define WR_STATUS  (_BV(TXINI) | _BV(STALLEDI))
#define RD_DATA    (_BV(TXINI) | _BV(FIFOCON))


; Program entry

; Save and clear MCUSR
; WDRF must be cleared to disable the watchdog timer.

	; Original MCUSR is preserved in r2 for user program
	; mcusr = MCUSR
	in r2, _SFR_IO_ADDR(MCUSR)
	; MCUSR = 0
	eor ZERO_REG, ZERO_REG
	out _SFR_IO_ADDR(MCUSR), ZERO_REG

; Disable watchdog

	; set_wdt(0)
	eor r18, r18
	rcall set_wdt

; Busy loop pause for USB detach during reset.
; This ensures that the host detects detach before restart. Typically the
; oscillator/PLL startup delays will exceed the specified USB max detach
; detection timing (2.5 us), but this is here anyway for robustness.

	; r18 = zero on entry
	; loops 256 times * 3 cycles = 768 cycles
start_delay:
	; while (--r18) {}
	dec r18            ; 1 cycle
	brne start_delay   ; 2 cycles

; Jump to user code if reset was:
; - brown-out
; - watchdog (except if external reset also set)
; - power-on
; - USB reset
;
; Watchdog + external reset triggers the bootloader in case WDTON is set
; since the watchdog may fire while the reset button is being held down.
;
; User code can enter the bootloader by triggering any other reset,
; or by following the instructions at the top of this file.

	mov r16, r2
	; if (mcusr != (_BV(WDRF)|_BV(EXTRF))
	cpi r16, _BV(EXTRF)|_BV(WDRF)
	breq wdt_setup
	;     && (mcusr & (_BV(BORF)|_BV(WDRF)|_BV(PORF)|_BV(USBRF)))) {
	andi r16, _BV(BORF)|_BV(WDRF)|_BV(PORF)|_BV(USBRF)
	breq wdt_setup
	;   vector_0();
	jmp 0x0000    ; jump to user program
	; }

; Enable watchdog for bootloader

wdt_setup:
	; set_wdt(_BV(WDE))
	ldi r18, _BV(WDE)
	rcall set_wdt

; Hardware initialization

; PLL configuration
; PINDIV = 0 for 8 MHz oscillator/crystal
; PINDIV = 1 for 16 MHz oscillator/crystal

#ifdef OSC_MHZ_8
#define PLLCSR_PINDIV 0
#endif  // OSC_MHZ_8

#ifdef OSC_MHZ_16
#define PLLCSR_PINDIV 1
#endif  // OSC_MHZ_16

#ifndef PLLCSR_PINDIV
#error config error: you must setup oscillator configuration
#endif  // !PLLCSR_PINDIV

; PLL initialization
; PINDIV = 0 or 1 (depending on oscillator setup), PLLE = 1
; PDIV3:0 = 0100 (equals reset value)

pll_setup:
	; PLLCSR = (_BV(PINDIV) * PLLCSR_PINDIV) | _BV(PLLE)
	ldi r16, (_BV(PINDIV) * PLLCSR_PINDIV) | _BV(PLLE)
	out _SFR_IO_ADDR(PLLCSR), r16

pll_wait:
	; loop_until_bit_is_set(PLLCSR, PLOCK)
	in r0, _SFR_IO_ADDR(PLLCSR)
	sbrs r0, PLOCK
	rjmp pll_wait

; Setup Y register for indirect addressing

	; r28 = lo(YBASE)
	; Note: r29 aka ZERO_REG is setup during MCUSR check
	ldi r28, YBASE & 0xff

; USB initialization

usb_setup:
#ifdef USB_REGULATOR
	; UHWCON = _BV(UVREGE)
	ldi r16, _BV(UVREGE)
	std y+YDISP(UHWCON), r16  ; set UVREGE
#endif  // USB_REGULATOR
	; The first store does not set OTGPADE because clock is not enabled.
	; Using the same value for both stores saves program space.
	; USBCON = _BV(USBE) | _BV(OTGPADE)
	ldi r16, _BV(USBE) | _BV(OTGPADE)
	std y+YDISP(USBCON), r16  ; set USBE
	; USBCON = _BV(USBE) | _BV(OTGPADE)
	std y+YDISP(USBCON), r16  ; set OTGPADE
	; UDCON = 0
#ifdef USB_LOW_SPEED
	ldi r16, _BV(LSM)
	std y+YDISP(UDCON), r16         ; set LSM=1, DETACH=0
#else
	std y+YDISP(UDCON), ZERO_REG    ; set DETACH=0
#endif


; Main loop
; Exits only by watchdog reset triggered by REBOOT command.

	; Register assignments in all states:
	;   r2        cmd      see above
	;   r3        state    see above
	;   r20       ledoff   FRNUM when LED should turn off
	;   r26:r27   len      length of current transaction
	;   r28:r29   YBASE    Y-register always equals YBASE
	;   r30:r31   ptr      memory pointer (varies by command type)

	; Loop entry and initialization
	; Note: ledoff is deliberately left uninitalized. This has no effect

main:
	; state = SETUP
	mov r3, ZERO_REG

#ifdef USE_LED
#if !defined(LED_DDR_REG) || !defined(LED_PORT_REG) || !defined(LED_IONUM)
#error config error: you must setup LED configuration
#endif
	; Enable LED output pin
	; LED_DDR_REG |= _BV(LED_IONUM)
	sbi _SFR_IO_ADDR(LED_DDR_REG), LED_IONUM
#endif  // USE_LED

	; Main loop body
loop:
	; Clear watchdog
	wdr

        ; Check for USB reset
	; if (UDINT & _BV(EORSTI)) {
	ldd r0, y+YDISP(UDINT)
	sbrs r0, EORSTI
	rjmp blink

	;   // reset USB module and setup endpoint
	;   UECONX = EPEN;
	ldi r24, _BV(EPEN)
	std y+YDISP(UECONX), r24
	;   UECFG1X = _BV(EPSIZE1) | _BV(EPSIZE0) | _BV(ALLOC);
	ldi r24, _BV(EPSIZE1) | _BV(EPSIZE0) | _BV(ALLOC)
	std y+YDISP(UECFG1X), r24

	;   // clear interrupts
	;   UDINT = 0;
	std y+YDISP(UDINT), ZERO_REG
	;   UEINTX = 0;
	std y+YDISP(UEINTX), ZERO_REG
	; }

	; USB activity LED
	; - turns on when state != SETUP
	; - turns off 20 ms after state == SETUP
blink:
#ifdef USE_LED
#ifndef USB_LOW_SPEED
	; // USB frame number (inc once per ms by SOF token)
	; frame = UDFNUML;
	ldd r0, y+YDISP(UDFNUML)
	; if (frame < ledoff) {
	cp r0, r20
	brlo led_noclr
#endif
	;   LED_PORT_REG &= ~_BV(LED_IONUM);
	cbi _SFR_IO_ADDR(LED_PORT_REG), LED_IONUM
led_noclr:
	; }
	; if (state != SETUP) {
	tst r3
	breq led_noset
#ifndef USB_LOW_SPEED
	;   ledoff = frame + 20;
	mov r20, r0
	subi r20, -20
#endif
	;   LED_PORT_REG |= _BV(LED_IONUM);
	sbi _SFR_IO_ADDR(LED_PORT_REG), LED_IONUM
led_noset:
	; }
#endif  // USE_LED

	; Endpoint handling
	;
	; Register assignment:
	;   r16 = intx (clobbered by SETUP handling)

intx:
	; Check for USB endpoint events
	; intx = UEINTX
	ldd r16, y+YDISP(UEINTX)

	; Check for SETUP token
	; if (intx & _BV(RXSTPI)) goto handle_state;
	sbrs r16, RXSTPI
	rjmp handle_state

	; Handle SETUP token
	;
	; The 8 byte SETUP token is copied into r2 through r9.
	;    r2 = bmRequestType
	;    r3 = bRequest
	;    r4 = wValueL
	;    r5 = wValueH
	;    r6 = wIndexL
	;    r7 = wIndexH
	;    r8 = wLengthL
	;    r9 = wLengthH
	;
	; r24 = command
	; r25 = state
	; These are copied to r2:r3 upon setup completion

	; copy 8 bytes from UEDATX to r2:r9
	; ptr = 0x0002 (r2 in data space)
	ldi r30, 2
	mov r31, ZERO_REG
	; do {
copy_setup:
	;   *ptr++ = UEDATX
	ldd r0, y+YDISP(UEDATX)
	st Z+, r0
	; } while (ptr != 0x0010);
	cpi r30, 10
	brne copy_setup

	; clear interrupts
	std y+YDISP(UEINTX), ZERO_REG

	; Parse setup packet

	; STALL if bmRequestType has any bit 0-5 set
	;       or bRequest      has any bit 4-7 set
	;
	; The command value is the bit-wise OR of these two values where
	;   bits 0-3 = bits 0-3 of bRequest
	;   bits 4-5 = 0
	;   bits 6-7 = bits 6-7 of bmRequestType

	; if ((bmRequestType & 0x3f) != 0 || (bRequest & 0xf0) != 0) goto stall
	movw r24, r2
	andi r24, 0x3f
	brne stall
	andi r25, 0xf0   ; r25 set by movw
	brne stall

	; Setup memory pointer.
	; Most commands want this, so do it unconditionally to save space.

	; ptr = wValue
	movw r30, r4

	; See USB commands above
	; cmd = bmRequestType | bRequest
	or r2, r3
	mov r24, r2

	; Descriptor handling

	; if (cmd == CMD_GET_DESC)
	cpi r24, CMD_GET_DESC
	brne setup_set_addr
	; // GET_DESCRIPTOR command
	; if (wValueH == DEVICE_DESCRIPTOR) {
	mov r25, r5
	cpi r25, DEVICE_DESCRIPTOR
	;   // Setup reading device descriptor
	brne setup_conf_desc
	;   size = sizeof(dev_desc)
	ldi r26, lo8(dev_desc_size)
	;   ptr = &dev_desc
	ldi r30, lo8(dev_desc)
	ldi r31, hi8(dev_desc)
	; }
	rjmp setup_desc_done

setup_conf_desc:
	; if (wValueH == CONFIG_DESCRIPTOR) {
	cpi r25, CONFIG_DESCRIPTOR
	brne stall
	;   // Setup reading config descriptor
	;   size = sizeof(conf_desc)
	ldi r26, lo8(conf_desc_size)
	;   ptr = &conf_desc
	ldi r30, lo8(conf_desc)
	ldi r31, hi8(conf_desc)
	; }
	; rjmp omitted to save insn

	; Descriptor reads can be short because host may read a prefix of either
	; descriptor during enumeration (e.g. for bMaxPacketSize0)
setup_desc_done:
	; if (wLength < len) {
	cp r8, r26
	cpc r9, ZERO_REG
	brcc setup_done_nolen
	; rjmp omitted to save insn

	; Set cmd = CMD_GET_DESC for program memory reads
	; which are implemented exactly the same as descriptor reads
setup_get_pmem_done:
	ldi r24, CMD_GET_DESC

	; Common SETUP token finalization
	; For non-descriptor control reads the host must always request
	; exact correct length or buffer overrun error occurs.
setup_done:
	;   len = wLength;
	movw r26, r8
setup_done_nolen:
	; }
	; state = cmd & 0x80 ? RD_DATA : WR_DATA
	ldi r25, WR_DATA
	sbrc r2, 7
	ldi r25, RD_DATA
	; cmd = r24
	; state = r25
	movw r2, r24
	rjmp loop

stall:
	; Bad request: STALL endpoint
	ldi r24, _BV(STALLRQ) | _BV(EPEN)
	std y+YDISP(UECONX), r24
	mov r3, ZERO_REG
	rjmp loop

	; The following commands are no-ops during setup
	; See state machine handling below for specific behavior

setup_set_addr:
	; if (cmd == CMD_SET_ADDR)
	cpi r24, CMD_SET_ADDR
	breq setup_done

setup_set_conf:
	; if (cmd == CMD_SET_CONF)
	cpi r24, CMD_SET_CONF
	breq setup_done

setup_reboot:
	; if (cmd == CMD_REBOOT)
	cpi r24, CMD_REBOOT
	breq setup_done

setup_get_eeprom:
	; if (cmd == CMD_GET_EEPROM)
	cpi r24, CMD_GET_EEPROM
	breq setup_done

setup_set_eeprom:
	; if (cmd == CMD_SET_EEPROM)
	cpi r24, CMD_SET_EEPROM
	breq setup_done

	; Signature read
	; This reads the bytes directly into UEDATX during setup
	; The state machine read loop is not used

setup_get_sigrd:
	; if (cmd == CMD_GET_SIGRD)
	cpi r24, CMD_GET_SIGRD
	brne setup_get_lock
	; read signature row via SIGRD bit
	;   0000 = signature[0]
	;   0002 = signature[0]
	;   0004 = signature[0]
	ldi r16, _BV(SIGRD)|_BV(SPMEN)
	ldi r17, 2
	ldi r18, 6
	; fall-through to setup_rd_spm

	; read special bytes through SPMCSR/LPM
	; r16 = SPMCSR value
	; r17 = lo(Z) stride
	; r18 = lo(Z) limit
setup_rd_spm:
	; Z = 0
	mov r30, ZERO_REG
	mov r31, ZERO_REG
	; do {
setup_rd_spm_loop:
	;   UEDATX = load byte from special SPM row
	out _SFR_IO_ADDR(SPMCSR), r16
	lpm r0, Z
	std y+YDISP(UEDATX), r0
	;   lo(Z) += stride
	add r30, r17
	; } while (lo(Z) != limit);
	cp r30, r18
	brne setup_rd_spm_loop
	rjmp setup_done

	; Lock/fuse read
	; This also reads directly into UEDATX during setup
	; The state machine read loop is not used

setup_get_lock:
	; if (cmd == CMD_GET_LOCK)
	cpi r24, CMD_GET_LOCK
	brne setup_get_pmem
	; read fuse/lock bytes via BLBSET bit
	;   0000 = low fuse
	;   0001 = lock byte
	;   0002 = ext fuse
	;   0003 = high fuse
	ldi r16, _BV(BLBSET)|_BV(SPMEN)
	ldi r17, 1
	ldi r18, 4
	rjmp setup_rd_spm

	; Read from program memory
	; Nothing to do except set CMD_GET_DESC

setup_get_pmem:
	; if (cmd == CMD_GET_PMEM)
	cpi r24, CMD_GET_PMEM
	; same logic as CMD_GET_DESC
	breq setup_get_pmem_done

	; Write to program memory
	; Enforces that pointer/length are page-aligned
	; And decrements pointer by one page (see state machine below)

setup_set_pmem:
	; if (cmd == CMD_SET_PMEM)
	cpi r24, CMD_SET_PMEM
	brne stall
	; if (lo(len) & 0x7f != 0) || (lo(ptr) & 0x7f) != 0) goto stall
	mov r17, r26
	or r17, r30
	andi r17, 0x7f
	brne stall
	; move ptr back one page
	; ptr -= 0x80
	subi r30, 0x80
	sbc r31, ZERO_REG
	; reset temporary page
	rcall do_spm_rwwsre
	rjmp setup_done

	; Endpoint state machine handling
	;
	; Each loop iteration handles at most one UEINTX bit.
	; See USB control endpoint state machine above.
	;
	; At the very end this stores intx to UEINTX to clear handled bits
	; The endpoint handling code may clear bits in intx as required

handle_state:
	; Compute next bit to process
	;
	; Note that when state == SETUP the following code does nothing
	; because r17 = 0xff and r25 == 0
	; so this falls-through to set UEINTX = 0xff which has no effect

	; intx &= state
	and r16, r3
	; intx = ~(intx & -intx)
	mov r17, r16
	neg r17
	and r16, r17
	com r16

	; r24 = cmd
	; r25 = intx & state
	movw r24, r2
	and r25, r16

	; Control read TXINI: write data for host to UEINTX
	; Common loop contains command-specific handling
	; Implements flash/eeprom memory reads
	; Other reads already filled UEDATX and this is a no-op

rd_data:
	; if (ms == RD_DATA & ~_BV(TXINI)) {
	cpi r25, RD_DATA & ~_BV(TXINI)
	brne wr_data
	;   nb = MAX_PACKET  // max token size
	ldi r17, MAX_PACKET
rd_loop:
	;   while (len) {
	adiw r26, 0
	breq state_end

	; Flash memory reads
	; This implements both descriptor and program memory reads

	;     if (cmd == CMD_GET_DESC) {
	cpi r24, CMD_GET_DESC
	brne rd_eeprom
	;       UEDATX = pgm_read_byte(ptr++);
	lpm r0, Z+
	std y+YDISP(UEDATX), r0
	;     }

	; EEPROM memory reads

rd_eeprom:
	;     if (cmd == CMD_GET_EEPROM) {
	cpi r24, CMD_GET_EEPROM
	brne rd_next
	;       eear_setup()
	rcall eear_setup
	;       EECR |= _BV(EERE)
	sbi _SFR_IO_ADDR(EECR), EERE
	;       UEDATX = EEDR
	in r0, _SFR_IO_ADDR(EEDR)
	std y+YDISP(UEDATX), r0
	;     }
rd_next:
	;     len--;
	sbiw r26, 1
	;     if (!--nb) break;
	subi r17, 1
	brne rd_loop
	;   }
rd_done:
	; }
	; rjmp omitted to save insn

	; Control write RXOUTI: handle data from host in UEDATX
	; Unlike reads no common outer loop; each command implements its own.
	; Implements flash/eeprom memory writes

wr_data:
	; if (ms == WR_DATA & ~_BV(RXOUTI))
	cpi r25, WR_DATA & ~_BV(RXOUTI)
	brne wr_status_begin
	; nb = UEBCLX
	ldd r18, y+YDISP(UEBCLX)

	; Flash memory writes
	; The temporary buffer is filled from the payload one *word* at a time.
	;
	; Writes are always a multiple of page size and aligned to page boundaries.
	; Each OUT token comprises one half of the page temporary buffer.
	; The page is erased and written after every second token.
	;
	; ptr is decremented by one page during SETUP to avoid juggling here
	; At the beginning of each page it points to the *previous* page.
	; This is OK: SPM only uses low bits when filling the temporary buffer.
	;
	; After incrementing ptr for one page, ptr points to the *beginning* of the
	; page to program. No fixup adjustments are required.

	; if (cmd == CMD_SET_PMEM) {
	cpi r24, CMD_SET_PMEM
	brne wr_eeprom
spm_wr_loop:
	; for (; nb >= 2; nb -= 2) {
	subi r18, 2
	brcs spm_wr_done
	; r0 = UEDATX
	ldd r0, y+YDISP(UEDATX)
	; r1 = UEDATX
	ldd r1, y+YDISP(UEDATX)
	; do_spm(SPMEN)
	ldi r19, _BV(SPMEN)
	rcall do_spm
	; ptr += 2
	adiw r30, 2
	rjmp spm_wr_loop

	; Erase and write the page if buffer filled.
	; ptr now points at the *beginning* of the page.

spm_wr_done:
	; if (lo(ptr) & 0x7f == 0) {
	mov r18, r30
	andi r18, 0x7f
	brne mask_intx
	;   do_spm(PGERS|SPMEN)
	ldi r19, _BV(PGERS)|_BV(SPMEN)
	rcall do_spm
	;   do_spm(PGWRT|SPMEN)
	ldi r19, _BV(PGWRT)|_BV(SPMEN)
	rcall do_spm
	;   // re-enable read-while-write section
	;   do_spm(RWWSRE|SPMEN)
	rcall do_spm_rwwsre
	; }

	; EEPROM memory writes.
	; The hardware allows atomic byte-wise erase+write so this is easy.
	; Loops over the token payload writing each byte.

wr_eeprom:
	; if (cmd == CMD_SET_EEPROM)
	cpi r24, CMD_SET_EEPROM
	brne mask_intx
wr_eeprom_loop:
	;   while (len--) {
	subi r18, 1
	brcs mask_intx
	;     eear_setup()
	rcall eear_setup
	;     EEDR = UEDATX
	ldd r0, y+YDISP(UEDATX)
	out _SFR_IO_ADDR(EEDR), r0
	;     EECR |= _BV(EEMPM)
	sbi _SFR_IO_ADDR(EECR), EEMPE
	;     EECR |= _BV(EEPE)
	sbi _SFR_IO_ADDR(EECR), EEPE
	;     // wait for programming
	;     do {
eeprom_wait:
	;       wdr();
	wdr
	;     } while (EECR & _BV(EEPE));
	sbic _SFR_IO_ADDR(EECR), EEPE
	rjmp eeprom_wait
	rjmp wr_eeprom_loop
	;   }
	; }
	; rjmp omitted to save insn

	; Control write NAKINI: write finished
	; Implements SET_ADDRESS and REBOOT

wr_status_begin:
	; if (ms == WR_DATA & ~_BV(NAKINI)) {
	cpi r25, WR_DATA & ~_BV(NAKINI)
	brne wr_status_end
	;   mask &= ~_BV(TXINI)
	andi r16, ~_BV(TXINI)
	;   state = WR_STATUS
	ldi r25, WR_STATUS
	mov r3, r25
	; }
	; rjmp omitted to save insn

	; Set address

wr_status_end:
	; if (ms == WR_STATUS & ~_BV(TXINI)) {
	cpi r25, WR_STATUS & ~_BV(TXINI)
	brne mask_intx
	;   if (cmd == CMD_SET_ADDR) {
	cpi r24, CMD_SET_ADDR
	brne do_reboot
	;     UDADDR = wValueL
	std y+YDISP(UDADDR), r30
	;     UDADDR = wValueL | _BV(ADDEN)
	ori r30, 0x80
	std y+YDISP(UDADDR), r30
	;   }

	; Reboot to user code

do_reboot:
	;   if (cmd == CMD_REBOOT) {
	cpi r24, CMD_REBOOT
	brne state_end
reboot_loop:
	; trip watchdog for restart
	rjmp reboot_loop
state_end:
	;   }
	;   state = SETUP
	mov r3, ZERO_REG
	; }
	; rjmp omitted to save insn

mask_intx:
	std y+YDISP(UEINTX), r16
	rjmp loop


; Subroutines

	; EEPROM address setup subroutine
	; Sets EEAR = ptr++
	;
	; inputs:
	;   r30:r31 = address
	; outputs:
	;   r30:r31 = address + 1
	; clobbers:
	;   none
eear_setup:
	out _SFR_IO_ADDR(EEARL), r30
	out _SFR_IO_ADDR(EEARH), r31
	adiw r30, 1
	ret


	; Watchdog setup subroutine.
	; inputs:
	;   r18 = new WDTCSR
	; clobbers:
	;   r19
set_wdt:
	ldi r19, _BV(WDCE)|_BV(WDE)
	sts WDTCSR, r19
	sts WDTCSR, r18
	ret


	; Re-enable read-while-write section subroutine
	; also resets temporary page
do_spm_rwwsre:
	ldi r19, _BV(RWWSRE)|_BV(SPMEN)
	; intentional fall-through to do_spm


	; SPM subroutine
	; inputs:
	;   r19 = spmctrl = SPMCSR value
	; clobbers:
	;   r0
do_spm:
	; SPMCSR = spmctrl
	out _SFR_IO_ADDR(SPMCSR), r19
	spm
	; do {
spm_wait:
	;   wdr
	wdr
	; } while (bit_is_set(SPMCSR, SPMEN));
	in r0, _SFR_IO_ADDR(SPMCSR)
	sbrc r0, SPMEN
	rjmp spm_wait
	ret
