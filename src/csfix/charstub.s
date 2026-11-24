// Two hooks in CameraService::getCameraCharacteristics(cameraId, targetSdk, rotationOverride,
// const AttributionSourceState& clientAttribution, devicePolicy, CameraMetadata* cameraInfo)
// (module cameraserver; tools/patch_cs_chars.py). Both replace a `bl atrace_get_enabled_tags`
// (ATRACE_CALL begin/end checks) and tail-call it afterwards, so the traced behaviour is unchanged.
//   charenter  at 0xc15f8 (after the prologue: x21 = cameraInfo, x24 = &clientAttribution)
//              -> opcam_chars_enter(cameraInfo, attribution)
//   charexit   at 0xc1c5c (common exit; x19 = binder::Status* (sret), never reassigned)
//              -> opcam_chars_exit(status)
// x21/x24 are reused inside the function, so only the entry hook reads them. The shim keeps the
// cameraInfo pointer in a thread-local between the two calls (see src/shim/charfilter.cpp).
// libcsext_shim.so is already loaded (libcsextimpl.so dependency; RTLD_LOCAL, hence dlopen+dlsym).
    .text
    .globl charenter, charexit
charenter:
    stp  x29, x30, [sp, #-0x10]!
    mov  x29, sp
    adr  x0, lib
    mov  w1, #2                 // RTLD_NOW
    bl   dlopen
    cbz  x0, 1f
    adr  x1, sym_enter
    bl   dlsym
    cbz  x0, 1f
    mov  x9, x0
    mov  x0, x21
    mov  x1, x24
    blr  x9
1:  ldp  x29, x30, [sp], #0x10
    b    atrace_get_enabled_tags
charexit:
    stp  x29, x30, [sp, #-0x10]!
    mov  x29, sp
    adr  x0, lib
    mov  w1, #2
    bl   dlopen
    cbz  x0, 1f
    adr  x1, sym_exit
    bl   dlsym
    cbz  x0, 1f
    mov  x9, x0
    mov  x0, x19
    blr  x9
1:  ldp  x29, x30, [sp], #0x10
    b    atrace_get_enabled_tags
lib:       .asciz "libcsext_shim.so"
sym_enter: .asciz "opcam_chars_enter"
sym_exit:  .asciz "opcam_chars_exit"
    .balign 16
