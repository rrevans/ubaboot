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

#include <libusb-1.0/libusb.h>
#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>

#include <unistd.h> // for "sleep()" and "usleep()"

#include "../config.h"
#include "ubaboot.h"
#include "read_hex.h"

static uint16_t FLASH_END = 0x7FFF;

int dev_read(libusb_device_handle *handle, uint8_t request, unsigned char *data, uint16_t length) {
    return libusb_control_transfer(handle, DEV_READ, request, 0, 0, data, length, 0);
}

int dev_write(libusb_device_handle *handle, uint8_t request, unsigned char *data, uint16_t length) {
    return libusb_control_transfer(handle, DEV_WRITE, request, 0, 0, data, length, 0);
}

bool read_mem(libusb_device_handle *handle, uint8_t op, uint8_t *buffer, uint16_t address, uint32_t tsize, uint16_t blksize) {
    uint32_t received = 0;
    uint32_t remaining;
    uint16_t bsz;

    while (received < tsize) {
        remaining = tsize - received;
        bsz = (remaining < blksize) ? remaining : blksize;
        if (bsz != libusb_control_transfer(handle, DEV_READ, op, address+received, 0, buffer+received, bsz, 0)) {
            return false;
        }
        received += bsz;
    }
    return true;
}

bool write_mem(libusb_device_handle *handle, uint8_t op, uint8_t *buffer, uint16_t address, uint32_t tsize, uint16_t blksize) {
    uint32_t sent = 0;
    uint32_t remaining;
    uint8_t *newbuffer;

    while (sent < tsize) {
        remaining = tsize - sent;
        if (remaining < blksize) {
            newbuffer = malloc(blksize);
            memset(newbuffer, 0xFF, blksize);
            memcpy(newbuffer, buffer + sent, remaining);
        } else {
            newbuffer = buffer+sent;
        }
        if (blksize != libusb_control_transfer(handle, DEV_WRITE, op, address+sent, 0, newbuffer, blksize, 0)) {
            return false;
        }
        if (newbuffer != buffer+sent) {
            free(newbuffer);
        }
        sent += blksize;
        usleep(20000);
    }
    return true;
}

bool read_device_id(libusb_device_handle *handle, uint32_t *id) {
    unsigned char buffer[3];

    if (3 != dev_read(handle, GET_SIGNATURE, buffer, 3)) {
        return false;
    }
    *id = (uint32_t) buffer[0];
    *id <<= 8;
    *id |= (uint32_t) buffer[1];
    *id <<= 8;
    *id |= (uint32_t) buffer[2];
    return true;
}

bool read_fuses(libusb_device_handle *handle,
                uint8_t *lock,
                uint8_t *efuse,
                uint8_t *hfuse,
                uint8_t *lfuse) {
    unsigned char buffer[4];

    if (4 != dev_read(handle, GET_LOCK, buffer, 4)) {
        return false;
    }
    *lfuse = buffer[0];
    *lock  = buffer[1];
    *efuse = buffer[2];
    *hfuse = buffer[3];
    return true;
}

bool reboot(libusb_device_handle *handle) {
    return 0 != dev_write(handle, REBOOT, NULL, 0);
}

bool program_hex(libusb_device_handle *handle, char *filename) {
    hex_block *blocks = NULL;
    FILE *fd = fopen(filename, "r");
    if (fd == NULL) {
        fprintf(stderr, "Can't open the file %s\n", filename);
        return false;
    }
    blocks = read_hex_file(fd);
    if (blocks == NULL) {
        return false;
    }
    return true;
}

int dump_flash(libusb_device_handle *handle, char *filename) {
    bool first_line = true;
    int counter = 0;
    uint8_t crc = 0;
    FILE *fd = stdout;
    uint8_t memory[32768];

    if (!read_mem(handle, READ_FLASH, memory, 0, FLASH_END + 1, 512)) {
        fprintf(stderr, "Error while reading flash. Aborting.\n");
        return -5;
    }
    if (filename != NULL) {
        fd = fopen(filename, "w");
        if (fd == NULL) {
            fprintf(stderr, "Failed to open the filename %s to dump the memory. Aborting.\n", filename);
            return -6;
        }
    }

    for(uint8_t *p = memory; counter < FLASH_END + 1; p++, counter++) {
        if (counter%16 == 0) {
            if (!first_line) {
                crc = 256 - crc;
                fprintf(fd, "%02X\n", crc);
            }
            first_line = false;
            fprintf(fd, ":10%04X00",counter);
            crc = 16 + ((uint8_t)(counter % 256)) + ((uint8_t)(counter / 256));
        }
        fprintf(fd, "%02X", *p);
        crc += *p;
    }
    crc = 256 - crc;
    fprintf(fd, "%02X\n:00000001FF\n", crc);
    return 0;
}

int program_flash(libusb_device_handle *handle, char *filename) {
    hex_block *blocks = NULL, *pblock = NULL;
    uint8_t memory[32768];
    uint8_t memory2[32768];
    int p;
    uint16_t write_size = 0;

    FILE *fd = fopen(filename, "r");
    if (fd == NULL) {
        fprintf(stderr, "Failed to open hexadecimal file %s. Aborting.\n", filename);
        return -5;
    }
    blocks = read_hex_file(fd);
    if (blocks == NULL) {
        printf("Error\n");
        return -5;
    }
    memset(memory, 0xFF, 32768);
    for(pblock = blocks; pblock != NULL; pblock = pblock->next) {
        memcpy(memory + pblock->address, pblock->data, pblock->size);
        if ((pblock->address + pblock->size) > write_size) {
            write_size = pblock->address + pblock->size;
        }
    }
    if (write_size > (FLASH_END - 511)) {
        fprintf(stderr, "ERROR: the code will overwrite the bootloader. Aborting.\n");
        return -6;
    }
    fprintf(stderr, "Writing to flash %d bytes\n", write_size);
    if (!write_mem(handle, WRITE_FLASH, memory, 0, write_size, 512)) {
        fprintf(stderr, "Error while writing flash. Aborting.\n");
        return -5;
    }
    fprintf(stderr, "Verifying data\n");
    memset(memory2, 0xFF, 32768);
    if (!read_mem(handle, READ_FLASH, memory2, 0, write_size, 512)) {
        fprintf(stderr, "Error while verifing flash. Aborting.\n");
        return -5;
    }
    for(p=0; p<write_size; p++) {
        if (memory[p] != memory2[p]) {
            fprintf(stderr, "Error while verifying flash at index %d (0x%04X). Aborting.\n", p, p);
            return -5;
        }
    }
    free_hex_blocks(blocks);
    fprintf(stderr, "Flash correctly written. Rebooting.\n");
    reboot(handle);
    return 0;
}

void help() {
    printf("Usage: ubaboot [-w] [-h] COMMAND\n");
    printf("  Commands:\n");
    printf("    reboot:                reboot the board and run main program.\n");
    printf("    status:                returns the fuses and lock values.\n");
    printf("    read flash [file.hex]: reads the program memory and shows it in\n");
    printf("                           the screen or dumps it into a file.\n");
    printf("    write flash file.hex:  writes the data in 'file.hex' into the program memory\n");
    printf("    -r:                    if present, will retry once per second until the\n");
    printf("                           programming device is available.\n");
    printf("    -h:                    shows this help.\n");
}

int main(int argc, char **argv) {
    libusb_context *ctx = NULL;
    libusb_device_handle *handle;
    uint8_t memory[4];
    bool wait = false;
    int param_index = 1;
    enum Commands command;
    char *filename = NULL;
    uint32_t device_id;

    if (argc < 2) {
        help();
        return -1;
    }

    if (argv[1][0] == '-') {
        switch (argv[1][1]) {
        case 'r':
            wait = true;
            param_index++;
            break;
        case 'h':
            help();
            return 0;
        default:
            help();
            return -1;
        }
    }

    if (LIBUSB_SUCCESS != libusb_init(&ctx)) {
        fprintf(stderr, "Failed to initialize the USB library. Aborting.");
        exit(-1);
    }

    if (!strcmp(argv[param_index], "reboot")) {
        command = COMMAND_REBOOT;
    } else if (!strcmp(argv[param_index], "status")) {
        command = COMMAND_STATUS;
    } else if (!strcmp(argv[param_index], "read")) {
        if (argc < (param_index + 2)) {
            help();
            return -1;
        }
        if (!strcmp(argv[param_index+1], "flash")) {
            command = COMMAND_READ_FLASH;
        } else if(!strcmp(argv[param_index+1], "eeprom")) {
            command = COMMAND_READ_EEPROM;
        } else {
            help();
            return -1;
        }
        if (argc >= (param_index + 3)) {
            filename = argv[param_index+2];
        }
    } else if (!strcmp(argv[param_index], "write")) {
        if (argc < (param_index + 3)) {
            help();
            return -1;
        }
        if (!strcmp(argv[param_index+1], "flash")) {
            command = COMMAND_WRITE_FLASH;
        } else if(!strcmp(argv[param_index+1], "eeprom")) {
            command = COMMAND_WRITE_EEPROM;
        } else {
            help();
            return -1;
        }
        filename = argv[param_index+2];
    } else {
        help();
        return -1;
    }

    do {
        handle = libusb_open_device_with_vid_pid(ctx,
                                                 VENDOR_ID,
                                                 PRODUCT_ID);
        if (handle == NULL) {
            if (wait) {
                fprintf(stderr, "Can't find the device. Retrying.\n");
                sleep(1);
            } else {
                fprintf(stderr, "Can't find the device. Ensure that it's in programming mode.\n");
                exit(-2);
            }
        } else {
            break;
        }
    } while(1);


    if (!read_device_id(handle, &device_id)) {
        fprintf(stderr, "Can't read the device ID. Aborting.\n");
        return -3;
    }
    if (device_id != 0x001E9587) {
        fprintf(stderr, "Device ID is 0x%08X instead of 0x001E9587. Aborting.\n", device_id);
        return -4;
    }
    fprintf(stderr, "CPU ID: %08X\n", device_id);


    switch(command) {
    case COMMAND_REBOOT:
        reboot(handle);
        return 0;
    case COMMAND_STATUS:
        if (!read_fuses(handle, memory, memory+1, memory+2, memory+3)) {
            fprintf(stderr, "Failed to read the fuses.\n");
            return -5;
        }
        fprintf(stderr, "Fuses: lfuse: 0x%02X; hfuse: 0x%02X; efuse: 0x%02X; lock: 0x%02X\n", memory[3], memory[2], memory[1], memory[0]);
        return 0;
    case COMMAND_READ_FLASH:
        return dump_flash(handle, filename);
    case COMMAND_WRITE_FLASH:
        return program_flash(handle, filename);
    default:
        fprintf(stderr, "Command not yet implemented.\n");
        return -1;
    }
}
