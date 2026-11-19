// Link-time stand-in for the device's /system_ext/lib64/libextendfile.so: libapsfix.so only
// needs the DT_NEEDED entry (APS resolves its symbols from the real library at runtime).
void __stub(void){}
