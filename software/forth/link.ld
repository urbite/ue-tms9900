ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x0000, LENGTH = 4K
    RAM (rwx) : ORIGIN = 0x1000, LENGTH = 12K
}

SECTIONS
{
    /* Code */
    .text 0x1000:
    {
        *(.text*)
        *(.rodata*)
    } > RAM

    .data :
    {
        _data_start = .;
        *(.data*)
        _data_end = .;
    } > RAM

    .bss :
    {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    } > RAM

    /* Stack at top of RAM */
    _stack_top = ORIGIN(RAM) + LENGTH(RAM) - 36;

    /* Debug sections — address 0, no memory region, live in ELF only */
    .debug_info     0 : { *(.debug_info) }
    .debug_abbrev   0 : { *(.debug_abbrev) }
    .debug_line     0 : { *(.debug_line) }
    .debug_str      0 : { *(.debug_str) }
    .debug_loc      0 : { *(.debug_loc) }
    .debug_ranges   0 : { *(.debug_ranges) }
    .debug_frame    0 : { *(.debug_frame) }
    .debug_pubnames 0 : { *(.debug_pubnames) }
    .debug_aranges  0 : { *(.debug_aranges) }
    .debug_pubtypes 0 : { *(.debug_pubtypes) }
    .comment        0 : { *(.comment) }
}
