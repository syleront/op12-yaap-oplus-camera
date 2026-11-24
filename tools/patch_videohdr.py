# Hides the HDR (Dolby Vision) switch of the OnePlus camera's Video mode on YAAP. Dolby Vision never records
# there (the encoder for its profile can't be created), and at 60 fps the Video mode hangs with it on (camera
# opened, streams never configured): the top bar with the switch doesn't appear, so it can't be turned off again.
# In the Video modes (com/oplus/camera/module/a = commonVideo; ck/l QuickVideo extends it), everything about
# the switch goes through getSupportFunction("func_hdr"): whether key_video_hdr / key_video_dolby are offered
# (ck/u0.z4), whether HDR is on (a.Cd), BaseMode.U6, CameraManager.M0 / pj.s4.u (dispatch to the mode). This
# makes the Video mode report func_hdr as unsupported, so the switch is gone and a saved "on" is not used.
# The config switch (com.oplus.feature.video.dv.support) can't be used: see docs/NOTES.md (Dolby Vision).
# Edits baksmali output of classes12.dex in place.
# usage: patch_videohdr.py <com/oplus/camera/module/a.smali>
import sys

path = sys.argv[1]
src = open(path, encoding='utf-8').read()

head = ('.method public getSupportFunction(Ljava/lang/String;)Z\n'
        '    .registers 26\n'
        '\n'
        '    .line 1\n'
        '    move-object/from16 v0, p0\n')
if src.count(head) != 1:
    sys.exit('patch_videohdr: getSupportFunction(String) not found as expected')
if 'opcamera: no video HDR' in src:
    sys.exit('patch_videohdr: already patched')
start = src.find(head)
body = src[start:src.find('.end method', start)]
if body.count('const-string v5, "func_hdr"') != 1:
    sys.exit('patch_videohdr: func_hdr case not found exactly once')

# p1 is v25 (> v15), so copy it to v1 first (v0 and v1 are set from p0/p1 right after anyway)
skip = ('    # opcamera: no video HDR (Dolby Vision)\n'
        '    move-object/from16 v1, p1\n'
        '    const-string v0, "func_hdr"\n'
        '    invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\n'
        '    move-result v0\n'
        '    if-eqz v0, :opcamera_hdr_keep\n'
        '    const/4 v0, 0x0\n'
        '    return v0\n'
        '    :opcamera_hdr_keep\n')
new = head.replace('\n    .line 1\n', '\n' + skip + '\n    .line 1\n')
open(path, 'w', encoding='utf-8', newline='\n').write(src.replace(head, new))
print('patch_videohdr: func_hdr unsupported in com/oplus/camera/module/a (Video)')
