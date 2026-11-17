package com.syleront.opcamera.halswitch;

import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/** Quick settings tile: on = OnePlus HAL, off = YAAP HAL. Tap to switch. */
public class HalTileService extends TileService {
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override
    public void onStartListening() {
        if (Hal.switching) { show(Tile.STATE_UNAVAILABLE, "Switching…"); return; }
        new Thread(new Runnable() {
            @Override public void run() {
                final String r = Hal.run("get");
                main.post(new Runnable() {
                    @Override public void run() {
                        if (r.equals("oos")) show(Tile.STATE_ACTIVE, "OnePlus");
                        else if (r.equals("yaap")) show(Tile.STATE_INACTIVE, "YAAP");
                        else if (r.equals("noroot")) show(Tile.STATE_INACTIVE, "Needs root");
                        else show(Tile.STATE_UNAVAILABLE, "Module off");
                    }
                });
            }
        }, "hal-get").start();
    }

    @Override
    public void onClick() {
        Tile t = getQsTile();
        if (Hal.switching || t == null) return;
        if (t.getState() == Tile.STATE_UNAVAILABLE) {
            Hal.toast(this, "The OnePlus camera module is not active.");
            return;
        }
        if ("Needs root".contentEquals(t.getSubtitle() == null ? "" : t.getSubtitle())) {
            Hal.toast(this, Hal.message("noroot"));
            onStartListening();   // re-check, in case it was just granted
            return;
        }
        show(Tile.STATE_UNAVAILABLE, "Switching…");
        Hal.toggleAsync(this, null);
    }

    private void show(int state, String subtitle) {
        Tile t = getQsTile();
        if (t == null) return;
        t.setState(state);
        t.setLabel(getString(R.string.tile_label));
        t.setSubtitle(subtitle);
        t.updateTile();
    }
}
