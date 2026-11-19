    .text
    .globl cave
// Called instead of wouldEvictLocked(x0=mgr, x1=&shared_ptr<desc>, w2=0, x8=sret) in
// CameraService::handleEvictionsLocked. If the connecting package is in
// persist.vendor.camera.privapp.list (the OnePlus camera), give its descriptor the max
// cost (100) so it never shares the HAL with another app's session.
cave:
    stp  x29, x30, [sp, #-0x30]!
    mov  x29, sp
    stp  x0, x1, [sp, #0x10]
    str  x8, [sp, #0x20]
    ldr  x0, [sp, #0x98]        // caller's [sp,#0x68]: const std::string& package
    bl   isPriv
    tbz  w0, #0, 1f
    ldr  x1, [sp, #0x18]
    ldr  x9, [x1]               // ClientDescriptor*
    mov  w10, #100
    str  w10, [x9, #0x20]       // mCost
1:
    ldp  x0, x1, [sp, #0x10]
    ldr  x8, [sp, #0x20]
    mov  w2, wzr
    ldp  x29, x30, [sp], #0x30
    b    wouldEvict
