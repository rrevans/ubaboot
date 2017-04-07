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
