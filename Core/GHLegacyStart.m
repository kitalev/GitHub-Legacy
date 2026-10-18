#if defined(__arm__) && __ARM_ARCH == 6

__asm__(
    "    .text\n"
    "    .align 2\n"
    "    .arm\n"
    "    .globl start\n"
    "start:\n"
    "    ldr r0, [sp]\n"
    "    add r1, sp, #4\n"
    "    add r4, r0, #1\n"
    "    add r2, r1, r4, lsl #2\n"
    "    bic sp, sp, #7\n"
    "    mov r3, r2\n"
    "1:\n"
    "    ldr r4, [r3], #4\n"
    "    teq r4, #0\n"
    "    bne 1b\n"
    "    bl _main\n"
    "    b _exit\n"
);

#endif
