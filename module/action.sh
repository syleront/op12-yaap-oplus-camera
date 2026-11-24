#!/system/bin/sh
# Root manager "Action" button (KernelSU, Magisk, APatch): show the module's state.
# From a root shell:  sh action.sh
MODDIR=${0%/*}
. $MODDIR/common.sh

if [ ! -f $ACTIVE ]; then
    echo "The module is not active this boot."
else
    echo "Active: OnePlus camera on the $(rom_name) camera HAL."
    echo "Relinked ROM libraries: $(find $RL -type f 2>/dev/null | wc -l)"
    n=$(cams_count); echo "Cameras listed: $n"
    [ "$n" -ge 6 ] || echo "(expected 6 or more; if the camera doesn't work, send the log)"
fi
echo ""
echo "Log ($LOG), last lines:"
tail -n 8 $LOG 2>/dev/null
