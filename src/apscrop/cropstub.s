    .text
    .globl cropstub
// Called instead of APSMetadata::setMetadata(x0=meta, w1=ANDROID_SCALER_CROP_REGION, x2=int32 rect[4],
// w3=4) at libAlgoProcess's 5 offline-reprocess crop sites. Copies the rect, lets libapsfix fix the
// copy (AHardwareBuffer_lockPlaneX(CROP_MAGIC, rect copy, -, metadata)) and sets the copy; the caller's rect
// is untouched.
// Placed in the zero padding after the RX segment (0x70d3c0); the patch extends that PT_LOAD.
cropstub:
    stp  x29, x30, [sp, #-0x40]!
    mov  x29, sp
    stp  x0, x1, [sp, #0x10]
    str  x3, [sp, #0x20]
    ldp  x8, x9, [x2]
    stp  x8, x9, [sp, #0x30]
    add  x1, sp, #0x30
    mov  x3, x0                 // metadata (holds the HAL crop of the original capture)
    movz x0, #0x4f50
    movk x0, #0x4346, lsl #16   // CROP_MAGIC 0x43464f50
    bl   lockPlaneX
    ldp  x0, x1, [sp, #0x10]
    ldr  x3, [sp, #0x20]
    add  x2, sp, #0x30
    bl   setMetadata
    ldp  x29, x30, [sp], #0x40
    ret
