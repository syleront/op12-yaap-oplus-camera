# Hides the Hi-Res ("highPixel") and Pro video ("masterVideo"; "movie" on models without master video) modes
# of the OnePlus camera on YAAP: Pro video is green in low light and Hi-Res only works at 1x. The camera keeps its mode list in its own database
# (databases/mode_data.db) and reads it in xm/e.p() (DataBaseOperator.query); the config switches for these
# modes are read before the module's camera_unit_config is parsed, so they can't be used (docs/NOTES.md).
# This skips these rows when the list is read, the same way the method already skips the "sticker" mode,
# so it also works on a list saved before the patch. Edits baksmali output of classes12.dex in place.
# usage: patch_modelist.py <xm/e.smali>
import sys

path = sys.argv[1]
src = open(path, encoding='utf-8').read()

start = src.find('.method public final p(Ljava/lang/String;ZZ)Ljava/util/ArrayList;')
end = src.find('.end method', start)
if start < 0 or end < 0:
    sys.exit('patch_modelist: method xm/e.p() not found')
body = src[start:end]

# the mode name is read into v4 (getString of "mode_name"), then compared with "sticker" using v1 as scratch;
# :goto_5d is the loop head (moveToNext), where the sticker check jumps back to
need = ['const-string p2, "mode_name"', 'move-result-object v4', '    :goto_5d\n', 'return-object v0']
for n in need:
    if body.count(n) != 1:
        sys.exit('patch_modelist: unexpected p(): %r found %d times' % (n, body.count(n)))
anchor = '    const-string v1, "sticker"\n\n    .line 169\n    .line 170\n    invoke-virtual {v1, v4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\n'
if body.count(anchor) != 1:
    sys.exit('patch_modelist: sticker check not found exactly once in p()')
if body.find(anchor) < body.find('move-result-object v4'):
    sys.exit('patch_modelist: sticker check before the mode name read')
if 'opcamera: hidden modes' in src:
    sys.exit('patch_modelist: already patched')

skip = '    # opcamera: hidden modes\n'
for name in ('highPixel', 'masterVideo', 'movie'):
    skip += ('    const-string v1, "%s"\n'
             '    invoke-virtual {v1, v4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\n'
             '    move-result v1\n'
             '    if-nez v1, :goto_5d\n\n' % name)

body = body.replace(anchor, skip + anchor)
open(path, 'w', encoding='utf-8', newline='\n').write(src[:start] + body + src[end:])
print('patch_modelist: highPixel, masterVideo and movie skipped in xm/e.p()')
