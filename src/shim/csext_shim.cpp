// Shim for OOS libcsextimpl.so on YAAP.
// libcsextimpl.so needs three CameraSessionStats constants that DerpFest's
// patched libcamera_client.so exports but YAAP's does not. Values are taken from
// DerpFest's libcamera_client.so (.rodata @0x261d0): EXCEPTION=4,
// SESSION_CONFIGURED=5, FIRST_FRAME_ARRIVED=6 (OPEN..CLOSED = 0..3 match YAAP).
// Linked only into libcsextimpl.so via DT_NEEDED, so only cameraserver sees it.
#include <cstdint>
namespace android { namespace hardware {
class CameraSessionStats {
  public:
    static const int CAMERA_STATE_EXCEPTION;
    static const int CAMERA_STATE_SESSION_CONFIGURED;
    static const int CAMERA_STATE_FIRST_FRAME_ARRIVED;
};
__attribute__((visibility("default"))) const int CameraSessionStats::CAMERA_STATE_EXCEPTION = 4;
__attribute__((visibility("default"))) const int CameraSessionStats::CAMERA_STATE_SESSION_CONFIGURED = 5;
__attribute__((visibility("default"))) const int CameraSessionStats::CAMERA_STATE_FIRST_FRAME_ARRIVED = 6;
}}
