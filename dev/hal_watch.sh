#!/system/bin/sh
# Camera HAL auto-switcher: YAAP's HAL by default, OnePlus HAL only while the OPlus camera is used.
# Invariant: while YAAP's HAL is active the OPlus camera process is not running, so it can never
# open a camera on the wrong HAL (it would hit a camera error and kill itself).
#   sh hal_watch.sh            (runs forever; log in $LOG)
SW=${SW:-/data/local/tmp/hal_switch.sh}
LOG=${LOG:-/data/local/tmp/hal_watch.log}
IDLE=${IDLE:-20}        # seconds the OPlus camera may sit in background before we go back to YAAP HAL
OPLUS=com.oplus.camera
# apps that should get YAAP's HAL right away (prefix match on package / activity class)
YAAP_APPS=${YAAP_APPS:-"org.lineageos.aperture com.google.android.apps.googlecamera com.google.android.GoogleCamera com.particlesdevs.photoncamera com.hinnka.mycamera com.meitu.meiyancamera"}
FIFO=/dev/opc_hal_watch.fifo

log()   { echo "$(date +%T) $*" >> $LOG; }
now()   { awk '{printf "%d", $1}' /proc/uptime; }
is_oos(){ sh $SW status | grep -q oos; }
cam_busy() {   # 0 = some app has a camera open
    dumpsys media.camera 2>/dev/null | awk '/^Active Camera Clients:/{getline; getline; f=($0 ~ /^\(Camera ID/); exit} END{exit !f}'
}
is_yaap_app() { for p in $YAAP_APPS; do case "$1" in "$p"*) return 0;; esac; done; return 1; }
sw() { log "-> $1 ($2)"; sh $SW "$1" >> $LOG 2>&1; switched_at=$(now); }
to_yaap() {    # stop the (background) OPlus camera first, then switch
    [ -n "$(pidof $OPLUS)" ] && { log "stopping background $OPLUS"; am force-stop $OPLUS; }
    sw yaap "$1"
}

fg=0; last_act=""; left_at=0; switched_at=0
# boot / restart: enforce the invariant
if ! is_oos && [ -n "$(pidof $OPLUS)" ]; then am force-stop $OPLUS; fi
is_oos && left_at=$(now)   # started while on OnePlus HAL: let the idle timer bring us back
log "watcher start (idle=${IDLE}s) $(sh $SW status)"
while true; do
    rm -f $FIFO; mkfifo $FIFO
    logcat -b events -T 1 -v brief am_proc_start:I am_proc_died:I wm_on_resume_called:I wm_on_stop_called:I '*:S' > $FIFO 2>/dev/null &
    LPID=$!
    exec 3< $FIFO
    while kill -0 $LPID 2>/dev/null; do
        t_read=$(now)
        if read -t 10 -u3 line; then
            case "$line" in
            *am_proc_start*",$OPLUS,"*)
                [ $fg = 0 ] && left_at=$(now)      # if it never comes to foreground, idle logic cleans up
                is_oos || sw oos "oplus process start" ;;
            *am_proc_died*",$OPLUS,"*|*am_proc_died*",$OPLUS]"*)
                if [ $fg = 1 ] && [ $(( $(now) - switched_at )) -lt 20 ]; then
                    log "oplus died right after a switch -> relaunching"; fg=0
                    is_oos || sw oos "relaunch"
                    am start -n $OPLUS/.Camera >/dev/null 2>&1
                else fg=0; left_at=$(now); fi ;;
            *wm_set_resumed_activity*"$OPLUS/"*|*wm_on_resume_called*"[$OPLUS".*|*wm_on_resume_called*",$OPLUS."*)
                fg=1; last_act=$(echo "$line" | grep -o "$OPLUS[./][A-Za-z0-9_.]*" | head -1)
                is_oos || sw oos "oplus resumed" ;;
            *wm_on_stop_called*",$OPLUS."*)
                act=$(echo "$line" | grep -o "$OPLUS\.[A-Za-z0-9_.]*" | head -1)
                case "$last_act" in *"${act#$OPLUS.}") fg=0; left_at=$(now); log "oplus left foreground";; esac ;;
            *am_proc_start*|*wm_on_resume_called*)
                # a third-party camera app is starting/resuming while the OnePlus HAL is up:
                # stop it (it must not hold a camera across the switch), switch, relaunch it
                for p in $YAAP_APPS; do case "$line" in *"$p"*) is_oos || break
                    # am_proc_start carries {pkg/.Activity}; wm_on_resume_called carries the full class name
                    comp=$(echo "$line" | grep -o -E "$p/[A-Za-z0-9_.\$]+" | head -1)
                    [ -z "$comp" ] && comp=$(echo "$line" | grep -o -E "$p\.[A-Za-z0-9_.\$]+" | head -1 | sed "s|^|$p/|")
                    log "$p starting on OnePlus HAL -> stop, switch, relaunch $comp"
                    am force-stop $p; fg=0; to_yaap "$p"; left_at=0
                    am start -n "$comp" >/dev/null 2>&1 || monkey -p $p 1 >/dev/null 2>&1
                    break;; esac; done ;;
            esac
        else
            [ "$(now)" = "$t_read" ] && sleep 1   # read failed instantly (EINTR/error): avoid busy loop
            # OPlus camera idle in background long enough and nobody holds a camera -> back to YAAP
            if [ $fg = 0 ] && [ $left_at -gt 0 ] && [ $(( $(now) - left_at )) -ge $IDLE ] && is_oos && ! cam_busy; then
                to_yaap "oplus idle ${IDLE}s"; left_at=0
            fi
        fi
    done
    exec 3<&-; log "logcat ended, restarting"; sleep 1
done
