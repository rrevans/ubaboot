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

#include <avr/pgmspace.h>
#include <stdint.h>
#include "config.h"
#include "packet.h"

#if !defined(VENDOR_ID) || !defined(PRODUCT_ID)
#error config error: you must setup USB vendor/device IDs
#endif

#define USB_DESCRIPTOR_TYPE_DEVICE          1
#define USB_DESCRIPTOR_TYPE_CONFIGURATION   2
#define USB_DESCRIPTOR_TYPE_INTERFACE       4
#define USB_BCD_VERSION_11                  0x0110

#define USBDESC(x) __attribute__((section(".usbdesc." x), used))

struct USB_DeviceDescriptor {
  uint8_t bLength;
  uint8_t bDescriptorType;
  uint16_t bcdUSB;
  uint8_t bDeviceClass;
  uint8_t bDeviceSubClass;
  uint8_t bDeviceProtocol;
  uint8_t bMaxPacketSize0;
  uint16_t idVendor;
  uint16_t idProduct;
  uint16_t bcdDevice;
  uint8_t iManufacturer;
  uint8_t iProduct;
  uint8_t iSerialNumber;
  uint8_t bNumConfigurations;
} __attribute__((packed));

const struct USB_DeviceDescriptor dev_desc USBDESC("device") = {
  .bLength = sizeof(struct USB_DeviceDescriptor),
  .bDescriptorType = USB_DESCRIPTOR_TYPE_DEVICE,
  .bcdUSB = USB_BCD_VERSION_11,
  .bDeviceClass = 0xff,
  .bDeviceSubClass = 0,
  .bDeviceProtocol = 0,
  .bMaxPacketSize0 = MAX_PACKET,
  .idVendor = VENDOR_ID,
  .idProduct = PRODUCT_ID,
  .bcdDevice = 0x0050,
  .bNumConfigurations = 1,
};

struct USB_ConfigurationDescriptor {
  uint8_t bLength;
  uint8_t bDescriptorType;
  uint16_t wTotalLength;
  uint8_t bNumInterfaces;
  uint8_t bConfigurationValue;
  uint8_t iConfiguration;
  uint8_t bmAttributes;
  uint8_t MaxPower;
} __attribute__((packed));

struct USB_InterfaceDescriptor {
  uint8_t bLength;
  uint8_t bDescriptorType;
  uint8_t bInterfaceNumber;
  uint8_t bAlternateSetting;
  uint8_t bNumEndpoints;
  uint8_t bInterfaceClass;
  uint8_t bInterfaceSubClass;
  uint8_t bInterfaceProtocol;
  uint8_t iInterface;
} __attribute__((packed));

struct USB_ConfigurationDescriptorSet {
  struct USB_ConfigurationDescriptor config;
  struct USB_InterfaceDescriptor ac_interface;
} __attribute__((packed));

const struct USB_ConfigurationDescriptorSet conf_desc USBDESC("config") = {
  .config = {
    .bLength = sizeof(struct USB_ConfigurationDescriptor),
    .bDescriptorType = USB_DESCRIPTOR_TYPE_CONFIGURATION,
    .wTotalLength = sizeof(struct USB_ConfigurationDescriptorSet),
    .bNumInterfaces = 1,
    .bConfigurationValue = 1,
    .bmAttributes = 0x80,
    .MaxPower = 50,  // 100mA
  },
  .ac_interface = {
    .bLength = sizeof(struct USB_InterfaceDescriptor),
    .bDescriptorType = USB_DESCRIPTOR_TYPE_INTERFACE,
    .bInterfaceNumber = 0,
    .bAlternateSetting = 0,
    .bNumEndpoints = 0,
    .bInterfaceClass = 0xff,
    .bInterfaceSubClass = 0,
    .bInterfaceProtocol = 0,
    .iInterface = 0,
  },
};
