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

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>

struct _hex_block {
    uint8_t size;
    uint16_t address;
    uint8_t type;
    uint8_t data[256];
    struct _hex_block *next;
};

typedef struct _hex_block hex_block;

void free_hex_blocks(hex_block *block);
hex_block* read_hex_file(FILE *fd);
