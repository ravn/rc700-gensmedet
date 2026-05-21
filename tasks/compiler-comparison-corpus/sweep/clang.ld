ENTRY(_start)
MEMORY {
  RAM (rwx) : ORIGIN = 0x0000, LENGTH = 0xC000
}
SECTIONS {
  .text 0x0000 : { *(.reset) *(.text*) } > RAM
  .rodata : { *(.rodata*) } > RAM
  .data : { *(.data*) } > RAM
  .bss : {
    __bss_start__ = .;
    *(.bss*)
    *(COMMON)
    __bss_end__ = .;
  } > RAM
}
