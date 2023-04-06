/*
 * Copyright 2023 Raster Software Vigo
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#define GET_SIGNATURE 1
#define READ_FLASH 2
#define WRITE_FLASH 3
#define REBOOT 4
#define READ_EEPROM 5
#define WRITE_EEPROM 6
#define GET_LOCK 7

#define DEV_READ 0xC0
#define DEV_WRITE 0x40

enum Commands { COMMAND_REBOOT,
                COMMAND_STATUS,
                COMMAND_READ_FLASH,
                COMMAND_READ_EEPROM,
                COMMAND_WRITE_FLASH,
                COMMAND_WRITE_EEPROM
              };

