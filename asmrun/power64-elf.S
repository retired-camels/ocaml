/*********************************************************************/
/*                                                                   */
/*                          Objective Caml                           */
/*                                                                   */
/*           Xavier Leroy, projet Cristal, INRIA Rocquencourt        */
/*                                                                   */
/* Copyright 1996 Institut National de Recherche en Informatique et  */
/* en Automatique.  All rights reserved.  This file is distributed   */
/* under the terms of the GNU Library General Public License, with   */
/* the special exception on linking described in file ../LICENSE.    */
/*                                                                   */
/*********************************************************************/

/* $Id: ocaml-3.11.0-ppc64.patch,v 1.1 2008/11/20 15:30:55 rjones Exp $ */

#define Addrglobal(reg,glob) \
        addis   reg, 0, glob@ha; \
        addi    reg, reg, glob@l
#define Loadglobal(reg,glob,tmp) \
        addis   tmp, 0, glob@ha; \
        ld     reg, glob@l(tmp)
#define Storeglobal(reg,glob,tmp) \
        addis   tmp, 0, glob@ha; \
        std     reg, glob@l(tmp)

        .section ".text"

/* Invoke the garbage collector. */

        .globl  caml_call_gc
        .type   caml_call_gc, @function
       .section ".opd","aw"
       .align 3        
caml_call_gc:
       .quad .L.caml_call_gc,.TOC.@tocbase
       .previous
       .align 2
.L.caml_call_gc:
    /* Set up stack frame */
        mflr    0
       std     0, 16(1)
    /* Record return address into Caml code */
        Storeglobal(0, caml_last_return_address, 11)
    /* Record lowest stack address */
        Storeglobal(1, caml_bottom_of_stack, 11)
    /* 0x220 = 8*32 (int regs) + 8*32 (float regs) + 48 (stack frame) */
        stdu    1, -0x230(1)
    /* Record pointer to register array */
        addi    0, 1, 8*32 + 48
        Storeglobal(0, caml_gc_regs, 11)
    /* Save current allocation pointer for debugging purposes */
        Storeglobal(31, caml_young_ptr, 11)
    /* Save exception pointer (if e.g. a sighandler raises) */
        Storeglobal(29, caml_exception_pointer, 11)
    /* Save all registers used by the code generator */
        addi    11, 1, 8*32 + 48 - 8
        stdu    3, 8(11)
        stdu    4, 8(11)
        stdu    5, 8(11)
        stdu    6, 8(11)
        stdu    7, 8(11)
        stdu    8, 8(11)
        stdu    9, 8(11)
        stdu    10, 8(11)
        stdu    14, 8(11)
        stdu    15, 8(11)
        stdu    16, 8(11)
        stdu    17, 8(11)
        stdu    18, 8(11)
        stdu    19, 8(11)
        stdu    20, 8(11)
        stdu    21, 8(11)
        stdu    22, 8(11)
        stdu    23, 8(11)
        stdu    24, 8(11)
        stdu    25, 8(11)
        stdu    26, 8(11)
        stdu    27, 8(11)
        stdu    28, 8(11)
        addi    11, 1, 48 - 8
        stfdu   1, 8(11)
        stfdu   2, 8(11)
        stfdu   3, 8(11)
        stfdu   4, 8(11)
        stfdu   5, 8(11)
        stfdu   6, 8(11)
        stfdu   7, 8(11)
        stfdu   8, 8(11)
        stfdu   9, 8(11)
        stfdu   10, 8(11)
        stfdu   11, 8(11)
        stfdu   12, 8(11)
        stfdu   13, 8(11)
        stfdu   14, 8(11)
        stfdu   15, 8(11)
        stfdu   16, 8(11)
        stfdu   17, 8(11)
        stfdu   18, 8(11)
        stfdu   19, 8(11)
        stfdu   20, 8(11)
        stfdu   21, 8(11)
        stfdu   22, 8(11)
        stfdu   23, 8(11)
        stfdu   24, 8(11)
        stfdu   25, 8(11)
        stfdu   26, 8(11)
        stfdu   27, 8(11)
        stfdu   28, 8(11)
        stfdu   29, 8(11)
        stfdu   30, 8(11)
        stfdu   31, 8(11)
    /* Call the GC */
       std     2,40(1)
        Addrglobal(11, caml_garbage_collection)
       ld      2,8(11)
       ld      11,0(11)
       mtlr    11
        blrl
       ld      2,40(1)
    /* Reload new allocation pointer and allocation limit */
        Loadglobal(31, caml_young_ptr, 11)
        Loadglobal(30, caml_young_limit, 11)
    /* Restore all regs used by the code generator */
        addi    11, 1, 8*32 + 48 - 8
        ldu    3, 8(11)
        ldu    4, 8(11)
        ldu    5, 8(11)
        ldu    6, 8(11)
        ldu    7, 8(11)
        ldu    8, 8(11)
        ldu    9, 8(11)
        ldu    10, 8(11)
        ldu    14, 8(11)
        ldu    15, 8(11)
        ldu    16, 8(11)
        ldu    17, 8(11)
        ldu    18, 8(11)
        ldu    19, 8(11)
        ldu    20, 8(11)
        ldu    21, 8(11)
        ldu    22, 8(11)
        ldu    23, 8(11)
        ldu    24, 8(11)
        ldu    25, 8(11)
        ldu    26, 8(11)
        ldu    27, 8(11)
        ldu    28, 8(11)
        addi    11, 1, 48 - 8
        lfdu    1, 8(11)
        lfdu    2, 8(11)
        lfdu    3, 8(11)
        lfdu    4, 8(11)
        lfdu    5, 8(11)
        lfdu    6, 8(11)
        lfdu    7, 8(11)
        lfdu    8, 8(11)
        lfdu    9, 8(11)
        lfdu    10, 8(11)
        lfdu    11, 8(11)
        lfdu    12, 8(11)
        lfdu    13, 8(11)
        lfdu    14, 8(11)
        lfdu    15, 8(11)
        lfdu    16, 8(11)
        lfdu    17, 8(11)
        lfdu    18, 8(11)
        lfdu    19, 8(11)
        lfdu    20, 8(11)
        lfdu    21, 8(11)
        lfdu    22, 8(11)
        lfdu    23, 8(11)
        lfdu    24, 8(11)
        lfdu    25, 8(11)
        lfdu    26, 8(11)
        lfdu    27, 8(11)
        lfdu    28, 8(11)
        lfdu    29, 8(11)
        lfdu    30, 8(11)
        lfdu    31, 8(11)
    /* Return to caller, restarting the allocation */
        Loadglobal(0, caml_last_return_address, 11)
        addic   0, 0, -16     /* Restart the allocation (4 instructions) */
        mtlr    0
    /* Say we are back into Caml code */
        li      12, 0
        Storeglobal(12, caml_last_return_address, 11)
    /* Deallocate stack frame */
        ld     1, 0(1)
    /* Return */
        blr
       .size .L.caml_call_gc,.-.L.caml_call_gc
       
/* Call a C function from Caml */

        .globl  caml_c_call
        .type   caml_c_call, @function
       .section ".opd","aw"
       .align 3        
caml_c_call:
       .quad .L.caml_c_call,.TOC.@tocbase
       .previous
       .align 2
.L.caml_c_call:
       .cfi_startproc
    /* Save return address */
        mflr    25
       .cfi_register lr,25
    /* Get ready to call C function (address in 11) */
       ld      2, 8(11)
        ld     11,0(11)
        mtlr    11
    /* Record lowest stack address and return address */
        Storeglobal(1, caml_bottom_of_stack, 12)
        Storeglobal(25, caml_last_return_address, 12)
    /* Make the exception handler and alloc ptr available to the C code */
        Storeglobal(31, caml_young_ptr, 11)
        Storeglobal(29, caml_exception_pointer, 11)
    /* Call the function (address in link register) */
        blrl
    /* Restore return address (in 25, preserved by the C function) */
        mtlr    25
    /* Reload allocation pointer and allocation limit*/
        Loadglobal(31, caml_young_ptr, 11)
        Loadglobal(30, caml_young_limit, 11)
    /* Say we are back into Caml code */
        li      12, 0
        Storeglobal(12, caml_last_return_address, 11)
    /* Return to caller */
        blr
        .cfi_endproc
       .size .L.caml_c_call,.-.L.caml_c_call
       
/* Raise an exception from C */

        .globl  caml_raise_exception
        .type   caml_raise_exception, @function
       .section ".opd","aw"
       .align 3        
caml_raise_exception:
       .quad .L.caml_raise_exception,.TOC.@tocbase
       .previous
       .align 2
.L.caml_raise_exception:
    /* Reload Caml global registers */
        Loadglobal(29, caml_exception_pointer, 11)
        Loadglobal(31, caml_young_ptr, 11)
        Loadglobal(30, caml_young_limit, 11)
    /* Say we are back into Caml code */
        li      0, 0
        Storeglobal(0, caml_last_return_address, 11)
    /* Pop trap frame */
       ld      0, 8(29)
       ld      1, 16(29)
        mtlr    0
       ld      2, 24(29)
       ld      29, 0(29)
    /* Branch to handler */
        blr
       .size .L.caml_raise_exception,.-.L.caml_raise_exception
       
/* Start the Caml program */

        .globl  caml_start_program
        .type   caml_start_program, @function
       .section ".opd","aw"
       .align 3        
caml_start_program:
       .quad .L.caml_start_program,.TOC.@tocbase
       .previous
       .align 2
.L.caml_start_program:
        Addrglobal(12, caml_program)

/* Code shared between caml_start_program and caml_callback */
.L102:
    /* Allocate and link stack frame */
        mflr    0
        std     0, 16(1)
        stdu    1, -0x190(1) /* 48 + 8*36(regs) + 32(callback) + 32(exc) */
    /* Save return address */
    /* Save all callee-save registers */
    /* GPR 14 ... GPR 31 then FPR 14 ... FPR 31 starting at sp+16 */
        addi    11, 1, 48-8
        stdu    14, 8(11)
        stdu    15, 8(11)
        stdu    16, 8(11)
        stdu    17, 8(11)
        stdu    18, 8(11)
        stdu    19, 8(11)
        stdu    20, 8(11)
        stdu    21, 8(11)
        stdu    22, 8(11)
        stdu    23, 8(11)
        stdu    24, 8(11)
        stdu    25, 8(11)
        stdu    26, 8(11)
        stdu    27, 8(11)
        stdu    28, 8(11)
        stdu    29, 8(11)
        stdu    30, 8(11)
        stdu    31, 8(11)
        stfdu   14, 8(11)
        stfdu   15, 8(11)
        stfdu   16, 8(11)
        stfdu   17, 8(11)
        stfdu   18, 8(11)
        stfdu   19, 8(11)
        stfdu   20, 8(11)
        stfdu   21, 8(11)
        stfdu   22, 8(11)
        stfdu   23, 8(11)
        stfdu   24, 8(11)
        stfdu   25, 8(11)
        stfdu   26, 8(11)
        stfdu   27, 8(11)
        stfdu   28, 8(11)
        stfdu   29, 8(11)
        stfdu   30, 8(11)
        stfdu   31, 8(11)
    /* Set up a callback link */
        Loadglobal(9, caml_bottom_of_stack, 11)
        Loadglobal(10, caml_last_return_address, 11)
        Loadglobal(11, caml_gc_regs, 11)
        std     9, 0x150(1)
        std     10, 0x158(1)
        std     11, 0x160(1)
    /* Build an exception handler to catch exceptions escaping out of Caml */
        bl      .L103
        b       .L104
.L103:
        mflr    0
        addi    29, 1, 0x170 /* Alignment */
       std     0, 8(29)
       std     1, 16(29)
       std     2, 24(29)
        Loadglobal(11, caml_exception_pointer, 11)
        std     11, 0(29)
    /* Reload allocation pointers */
        Loadglobal(31, caml_young_ptr, 11) 
        Loadglobal(30, caml_young_limit, 11)
    /* Say we are back into Caml code */
        li      0, 0
        Storeglobal(0, caml_last_return_address, 11)
    /* Call the Caml code */
       std     2,40(1)
       ld      2,8(12)
       ld      12,0(12)
        mtlr    12
.L105:
        blrl
       ld      2,40(1)
    /* Pop the trap frame, restoring caml_exception_pointer */
        ld     9, 0x170(1)
        Storeglobal(9, caml_exception_pointer, 11)
    /* Pop the callback link, restoring the global variables */
.L106:
        ld     9, 0x150(1)
        ld     10, 0x158(1)
        ld     11, 0x160(1)
        Storeglobal(9, caml_bottom_of_stack, 12) 
        Storeglobal(10, caml_last_return_address, 12) 
        Storeglobal(11, caml_gc_regs, 12) 
    /* Update allocation pointer */
        Storeglobal(31, caml_young_ptr, 11)
    /* Restore callee-save registers */
        addi    11, 1, 48-8
        ldu    14, 8(11)
        ldu    15, 8(11)
        ldu    16, 8(11)
        ldu    17, 8(11)
        ldu    18, 8(11)
        ldu    19, 8(11)
        ldu    20, 8(11)
        ldu    21, 8(11)
        ldu    22, 8(11)
        ldu    23, 8(11)
        ldu    24, 8(11)
        ldu    25, 8(11)
        ldu    26, 8(11)
        ldu    27, 8(11)
        ldu    28, 8(11)
        ldu    29, 8(11)
        ldu    30, 8(11)
        ldu    31, 8(11)
        lfdu    14, 8(11)
        lfdu    15, 8(11)
        lfdu    16, 8(11)
        lfdu    17, 8(11)
        lfdu    18, 8(11)
        lfdu    19, 8(11)
        lfdu    20, 8(11)
        lfdu    21, 8(11)
        lfdu    22, 8(11)
        lfdu    23, 8(11)
        lfdu    24, 8(11)
        lfdu    25, 8(11)
        lfdu    26, 8(11)
        lfdu    27, 8(11)
        lfdu    28, 8(11)
        lfdu    29, 8(11)
        lfdu    30, 8(11)
        lfdu    31, 8(11)
    /* Return */
        ld     1,0(1)
    /* Reload return address */
        ld     0, 16(1)
        mtlr    0
        blr

    /* The trap handler: */
.L104:
    /* Update caml_exception_pointer */
        Storeglobal(29, caml_exception_pointer, 11)
    /* Encode exception bucket as an exception result and return it */
        ori     3, 3, 2
        b       .L106
       .size .L.caml_start_program,.-.L.caml_start_program
       
/* Callback from C to Caml */

        .globl  caml_callback_exn
        .type   caml_callback_exn, @function
       .section ".opd","aw"
       .align 3        
caml_callback_exn:
       .quad .L.caml_callback_exn,.TOC.@tocbase
       .previous
       .align 2
.L.caml_callback_exn:
    /* Initial shuffling of arguments */
        mr      0, 3            /* Closure */
        mr      3, 4            /* Argument */
        mr      4, 0
        ld     12, 0(4)        /* Code pointer */
        b       .L102
       .size .L.caml_callback_exn,.-.L.caml_callback_exn

       
        .globl  caml_callback2_exn
        .type   caml_callback2_exn, @function
       .section ".opd","aw"
       .align 3        
caml_callback2_exn:
       .quad .L.caml_callback2_exn,.TOC.@tocbase
       .previous
       .align 2
.L.caml_callback2_exn:
        mr      0, 3            /* Closure */
        mr      3, 4            /* First argument */
        mr      4, 5            /* Second argument */
        mr      5, 0
        Addrglobal(12, caml_apply2)
        b       .L102
       .size .L.caml_callback2_exn,.-.L.caml_callback2_exn

       
        .globl  caml_callback3_exn
        .type   caml_callback3_exn, @function
       .section ".opd","aw"
       .align 3        
caml_callback3_exn:
       .quad .L.caml_callback3_exn,.TOC.@tocbase
       .previous
       .align 2
.L.caml_callback3_exn:
        mr      0, 3            /* Closure */
        mr      3, 4            /* First argument */
        mr      4, 5            /* Second argument */
        mr      5, 6            /* Third argument */
        mr      6, 0
        Addrglobal(12, caml_apply3)
        b       .L102
       .size .L.caml_callback3_exn,.-.L.caml_callback3_exn
       
/* Frame table */

        .section ".data"
        .globl  caml_system__frametable
        .type   caml_system__frametable, @object
caml_system__frametable:
        .quad   1               /* one descriptor */
        .quad   .L105 + 4       /* return address into callback */
        .short  -1              /* negative size count => use callback link */
        .short  0               /* no roots here */
        .align  3

