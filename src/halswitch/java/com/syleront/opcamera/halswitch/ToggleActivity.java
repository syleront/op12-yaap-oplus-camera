package com.syleront.opcamera.halswitch;

import android.app.Activity;
import android.os.Bundle;

/** Launcher icon: switches the camera HAL without showing any UI (result comes as a toast). */
public class ToggleActivity extends Activity {
    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        if (!Hal.switching) Hal.toast(this, "Switching camera HAL…");
        Hal.toggleAsync(this, null);
        finish();   // Theme.NoDisplay requires finishing before onResume
    }
}
