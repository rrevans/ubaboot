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

#include "read_hex.h"
#include <stdlib.h>
#include <stdio.h>

static int line_number;
static uint8_t crc;

static uint8_t hex_to_bin(FILE *fd) {
    uint8_t value, retval;

    if (1 != fread(&value, 1, 1, fd)) {
        return 0xFF;
    }

    if (value > 'Z') {
        value -= 32; // transform into uppercase
    }
    if (value >= 'A') {
        retval = value + 10 - 'A';
    } else {
        retval = value - '0';
    }
    if (retval > 15) {
        return 0xFF;
    } else {
        return retval;
    }
}

static bool read_hex_value(FILE *fd, uint8_t *value) {
    uint8_t buffer[2];
    buffer[0] = hex_to_bin(fd);
    buffer[1] = hex_to_bin(fd);
    if ((buffer[0] == 0xFF) || (buffer[1] == 0xFF)) {
        fprintf(stderr, "Invalid hexadecimal value at line %d.\n", line_number);
        return false;
    }
    *value = buffer[0] * 16 + buffer[1];
    crc += *value;
    return true;
}

static bool find_colon(FILE *fd) {
    uint8_t value;
    while (true) {
        if (1 != fread(&value, 1, 1, fd)) {
            return false;
        }
        if (value == ':') {
            line_number++;
            return true;
        }
    }
}

static hex_block* read_block(FILE *fd) {
    hex_block *retval = NULL;
    uint8_t tmp = 0, count, *p;

    if (!find_colon(fd)) {
        fprintf(stderr, "End-of-file block not found.\n");
        return NULL;
    }
    retval = malloc(sizeof(hex_block));
    if (retval == NULL) {
        fprintf(stderr, "Unable to reserve memory block.\n");
        return retval;
    }
    retval->next = NULL;
    crc = 0;
    if (!read_hex_value(fd, &tmp)) {
        fprintf(stderr, "Failed to read the address at line %d.\n", line_number);
        goto read_block_err;
    }
    retval->size = tmp;
    if (!read_hex_value(fd, &tmp)) {
        fprintf(stderr, "Failed to read the address at line %d.\n", line_number);
        goto read_block_err;
    }
    retval->address = 256 * ((uint16_t)tmp);
    if (!read_hex_value(fd, &tmp)) {
        goto read_block_err;
    }
    retval->address += (uint16_t)tmp;
    if (!read_hex_value(fd, &tmp)) {
        fprintf(stderr, "Failed to read the block type at line %d.\n", line_number);
        goto read_block_err;
    }
    retval->type = tmp;
    if ((tmp != 0) && (tmp != 1)) {
        fprintf(stderr, "Invalid block type %02X at line %d.\n", tmp, line_number);
        goto read_block_err;
    }
    for(p = retval->data, count = 0; count < retval->size; count++, p++) {
        if (!read_hex_value(fd, &tmp)) {
            fprintf(stderr, "Failed to read value at line %d.\n", line_number);
            goto read_block_err;
        }
        *p = tmp;
    }
    if (!read_hex_value(fd, &tmp)) {
        fprintf(stderr, "Failed to read the CRC at line %d.\n", line_number);
        goto read_block_err;
    }
    if (crc == 0) {
        return retval;
    } else {
        fprintf(stderr, "Incorrect CRC value, %02X, at line %d.\n", crc, line_number);
    }

read_block_err:
    free(retval);
    return NULL;
}

void free_hex_blocks(hex_block *block) {
    hex_block *tmp;
    while(block) {
        tmp = block->next;
        free(block);
        block = tmp;
    }
}

hex_block* read_hex_file(FILE *fd) {
    hex_block *blocks = NULL;
    hex_block *last_block = NULL;
    hex_block *block;

    line_number = 0;

    while (true) {
        block = read_block(fd);
        if (block == NULL) {
            free_hex_blocks(blocks);
            return NULL;
        }
        if (last_block == NULL) {
            last_block = blocks = block;
            continue;
        }
        last_block->next = block;
        last_block = block;
        if (block->type == 0x01) {
            break;
        }
    }
    return blocks;
}
