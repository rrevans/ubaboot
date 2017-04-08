/* Copyright 2017 by Robert Evans (rrevans@gmail.com)

   This file is part of ubaboot.

   ubaboot is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   ubaboot is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with ubaboot.  If not, see <http://www.gnu.org/licenses/>.
*/

MEMORY {
    FLASH (rx) : ORIGIN = 0x00007e00, LENGTH = 512
    RAM (rw) : ORIGIN = 0x00800100, LENGTH = 2K
}

SECTIONS {
    .text : {
        *(.text*)

        _usbdesc_device_begin = .;
        *(.usbdesc.device)
        _usbdesc_device_end = .;

        dev_desc = _usbdesc_device_begin;
        dev_desc_size = _usbdesc_device_end - _usbdesc_device_begin;

        _usbdesc_config_begin = .;
        *(.usbdesc.config)
        _usbdesc_config_end = .;

        conf_desc = _usbdesc_config_begin;
        conf_desc_size = _usbdesc_config_end - _usbdesc_config_begin;
    } > FLASH = 0xFF
}
