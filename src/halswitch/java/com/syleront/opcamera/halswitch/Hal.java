package com.syleront.opcamera.halswitch;

import android.content.ComponentName;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.TileService;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.util.concurrent.TimeUnit;

/** Talks to the KernelSU module's action.sh through su. All calls block: use a worker thread. */
final class Hal {
    static final String SCRIPT = "/data/adb/modules/opcamera_yaap/action.sh";
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    /** true while a switch started by this app is running (tile shows "Switching…") */
    static volatile boolean switching;

    private Hal() {}

    /**
     * Runs action.sh with one argument and returns its one-line answer:
     * oos | yaap | inactive (for "get"); ok &lt;hal&gt; | busy | inactive | locked | fail &lt;hal&gt; (for app-*);
     * or noroot | nomodule | error.
     */
    static String run(String arg) {
        Process p = null;
        try {
            p = new ProcessBuilder("su", "-c", "[ -f " + SCRIPT + " ] || { echo nomodule; exit 3; }; sh " + SCRIPT + " " + arg)
                    .redirectErrorStream(true).start();
            p.getOutputStream().close();
            StringBuilder out = new StringBuilder();
            try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
                String line;
                while ((line = r.readLine()) != null) {
                    if (!line.trim().isEmpty()) out.append(line.trim()).append('\n');
                }
            }
            if (!p.waitFor(45, TimeUnit.SECONDS)) { p.destroy(); return "error"; }
            String s = out.toString().trim();
            String last = s.isEmpty() ? "" : s.substring(s.lastIndexOf('\n') + 1);
            if (last.matches("(ok |fail )?(oos|yaap)|busy|inactive|locked|nomodule")) return last;
            // su refused / not granted: no answer from the script
            return "noroot";
        } catch (Exception e) {
            return "noroot";   // no su binary
        } finally {
            if (p != null) p.destroy();
        }
    }

    static String name(String hal) {
        return "oos".equals(hal) ? "OnePlus" : "yaap".equals(hal) ? "YAAP" : hal;
    }

    /** Message for a toast after a switch attempt, or null when nothing needs saying. */
    static String message(String r) {
        if (r.equals("ok oos")) return "Camera HAL: OnePlus. The OnePlus camera is ready.";
        if (r.equals("ok yaap")) return "Camera HAL: YAAP. Don't open the OnePlus camera now.";
        if (r.equals("busy")) return "A camera app is open. Close it and try again.";
        if (r.equals("locked")) return "A HAL switch is already running.";
        if (r.equals("inactive")) return "The OnePlus camera module is not active this boot.";
        if (r.equals("nomodule")) return "The OnePlus camera module is not installed.";
        if (r.startsWith("fail ")) return "Switch failed, HAL is " + name(r.substring(5)) + ". See /data/adb/opcamera/log.txt";
        if (r.equals("noroot")) return "Allow root for \"Camera HAL\" in KernelSU > Superuser.";
        return "Switch failed (" + r + ").";
    }

    static void toast(Context c, String msg) {
        final Context app = c.getApplicationContext();
        MAIN.post(new Runnable() {
            @Override public void run() { Toast.makeText(app, msg, Toast.LENGTH_LONG).show(); }
        });
    }

    static void refreshTile(Context c) {
        TileService.requestListeningState(c, new ComponentName(c, HalTileService.class));
    }

    /** Switch to the other HAL in the background; toast + tile refresh when done. */
    static void toggleAsync(Context c, Runnable onDone) {
        final Context app = c.getApplicationContext();
        if (switching) { toast(app, "A HAL switch is already running."); return; }
        switching = true;
        refreshTile(app);
        new Thread(new Runnable() {
            @Override public void run() {
                String r;
                try { r = Hal.run("app-toggle"); } finally { switching = false; }
                toast(app, message(r));
                refreshTile(app);
                if (onDone != null) MAIN.post(onDone);
            }
        }, "hal-switch").start();
    }

    static boolean moduleInstalled() { return new File("/data/adb/modules/opcamera_yaap").exists(); }
}
