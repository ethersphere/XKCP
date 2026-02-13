  
  Root Causes                                                                                                                                      
                                                                                                                                                 
  1. Go's internal linker doesn't resolve relocations in .syso files                                                                               
  - R_X86_64_PLT32 relocations (function calls between wrapper and XKCP) were left as e8 00 00 00 00, making every internal function call jump to  
  the next instruction instead of the target
  - R_X86_64_PC32 relocations (references to .rodata.cst32 / .rodata.cst8 for AVX2 constants) were also unresolved

  2. Assembly glue code bugs (keccak_times4_amd64.s)
  - Frame size $16 was way too small (C function needs ~2KB of stack)
  - ANDQ $-16, SP corrupted Go's stack pointer, breaking the return path

  Fixes Applied

  build_go_asm.sh - Complete rewrite with a pre-linking pipeline:
  1. Build XKCP library, extract .o files
  2. Compile go_wrapper.c → .o
  3. ld -r to combine wrapper + XKCP into one relocatable object
  4. Full ld link with a linker script to resolve ALL relocations (text + rodata contiguous)
  5. objcopy pipeline: binary extraction → ELF creation → section rename → flag fix → symbol restore
  6. Result: a .syso with zero relocations that Go's internal linker can consume

  keccak_times4_amd64.s - Fixed assembly glue:
  - Frame size increased to $8192 (covers C stack usage with headroom)
  - Removed the ANDQ $-16, SP corruption (C function handles its own alignment)

  go_keccak/go.mod - Removed golang.org/x/sys dependency (not needed)
