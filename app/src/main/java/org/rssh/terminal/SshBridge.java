package org.rssh.terminal;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.util.Base64;
import android.util.Log;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.widget.Toast;

import com.jcraft.jsch.Channel;
import com.jcraft.jsch.ChannelShell;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.Session;

import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

public class SshBridge {
    private static final String TAG = "SshBridge";
    private static final String PREFS_NAME = "rssh_terminal_profiles";
    private static final String KEY_PROFILES = "saved_sessions_json";

    private final Activity activity;
    private final WebView webView;
    private final Handler mainHandler;
    private final ExecutorService executor;
    private final SharedPreferences prefs;

    private JSch jsch;
    private Session session;
    private ChannelShell channel;
    private OutputStream outputStream;
    private PowerManager.WakeLock wakeLock;

    private final AtomicBoolean isConnected = new AtomicBoolean(false);
    private final AtomicBoolean isConnecting = new AtomicBoolean(false);

    public SshBridge(Activity activity, WebView webView) {
        this.activity = activity;
        this.webView = webView;
        this.mainHandler = new Handler(Looper.getMainLooper());
        this.executor = Executors.newCachedThreadPool();
        this.prefs = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        this.jsch = new JSch();
    }

    private void postToJs(String script) {
        mainHandler.post(() -> {
            if (webView != null) {
                webView.evaluateJavascript(script, null);
            }
        });
    }

    private void notifyStatus(String status, String message) {
        String safeMsg = message == null ? "" : message.replace("'", "\\'").replace("\n", " ");
        postToJs("if (window.onSshStatus) { window.onSshStatus('" + status + "', '" + safeMsg + "'); }");
    }

    @JavascriptInterface
    public void connect(String host, int port, String username, String authType, String secret, String passphrase, int cols, int rows) {
        if (isConnecting.get() || isConnected.get()) {
            disconnect();
        }

        isConnecting.set(true);
        notifyStatus("CONNECTING", "در حال برقراری اتصال به " + host + ":" + port + "...");

        executor.submit(() -> {
            try {
                jsch = new JSch();

                // Setup authentication
                if ("key".equalsIgnoreCase(authType) && secret != null && !secret.trim().isEmpty()) {
                    byte[] keyBytes = secret.getBytes(StandardCharsets.UTF_8);
                    byte[] passBytes = (passphrase != null && !passphrase.isEmpty()) ? passphrase.getBytes(StandardCharsets.UTF_8) : null;
                    jsch.addIdentity("id_rsa_custom", keyBytes, null, passBytes);
                }

                session = jsch.getSession(username, host, port <= 0 ? 22 : port);
                session.setConfig("StrictHostKeyChecking", "no");
                session.setConfig("PreferredAuthentications", "password,keyboard-interactive,publickey");
                
                if ("password".equalsIgnoreCase(authType) && secret != null) {
                    session.setPassword(secret);
                }

                notifyStatus("AUTHENTICATING", "در حال احراز هویت با نام کاربری " + username + "...");
                session.connect(15000); // 15 second connection timeout

                notifyStatus("INITIALIZING_SHELL", "راه‌اندازی ترمینال امن PTY...");
                Channel ch = session.openChannel("shell");
                channel = (ChannelShell) ch;
                
                int ptyCols = cols > 0 ? cols : 80;
                int ptyRows = rows > 0 ? rows : 24;
                channel.setPtyType("xterm-256color", ptyCols, ptyRows, ptyCols * 8, ptyRows * 16);
                
                InputStream in = channel.getInputStream();
                outputStream = channel.getOutputStream();

                channel.connect(10000);

                isConnected.set(true);
                isConnecting.set(false);
                notifyStatus("CONNECTED", "اتصال پایدار و امن SSH برقرار شد.");

                // Keep screen on during active SSH session
                acquireWakeLock();

                // Background reading loop
                byte[] buffer = new byte[8192];
                int read;
                while (isConnected.get() && (read = in.read(buffer)) != -1) {
                    if (read > 0) {
                        String b64 = Base64.encodeToString(buffer, 0, read, Base64.NO_WRAP);
                        postToJs("if (window.onTerminalDataB64) { window.onTerminalDataB64('" + b64 + "'); }");
                    }
                }

            } catch (Exception e) {
                Log.e(TAG, "SSH Connection error", e);
                String err = e.getMessage() != null ? e.getMessage() : e.toString();
                notifyStatus("ERROR", "خطای اتصال SSH: " + err);
            } finally {
                cleanUp();
            }
        });
    }

    @JavascriptInterface
    public void sendData(String text) {
        if (outputStream != null && isConnected.get()) {
            executor.submit(() -> {
                try {
                    outputStream.write(text.getBytes(StandardCharsets.UTF_8));
                    outputStream.flush();
                } catch (Exception e) {
                    Log.e(TAG, "Error writing data to SSH", e);
                }
            });
        }
    }

    @JavascriptInterface
    public void sendDataB64(String b64) {
        if (outputStream != null && isConnected.get() && b64 != null) {
            executor.submit(() -> {
                try {
                    byte[] data = Base64.decode(b64, Base64.NO_WRAP);
                    outputStream.write(data);
                    outputStream.flush();
                } catch (Exception e) {
                    Log.e(TAG, "Error writing b64 data to SSH", e);
                }
            });
        }
    }

    @JavascriptInterface
    public void resize(int cols, int rows) {
        if (channel != null && isConnected.get() && cols > 0 && rows > 0) {
            executor.submit(() -> {
                try {
                    channel.setPtySize(cols, rows, cols * 8, rows * 16);
                } catch (Exception e) {
                    Log.w(TAG, "Error resizing PTY: " + e.getMessage());
                }
            });
        }
    }

    @JavascriptInterface
    public void disconnect() {
        executor.submit(this::cleanUp);
    }

    private synchronized void cleanUp() {
        boolean wasConnected = isConnected.getAndSet(false);
        isConnecting.set(false);

        try {
            if (outputStream != null) {
                outputStream.close();
                outputStream = null;
            }
        } catch (Exception ignored) {}

        try {
            if (channel != null) {
                channel.disconnect();
                channel = null;
            }
        } catch (Exception ignored) {}

        try {
            if (session != null) {
                session.disconnect();
                session = null;
            }
        } catch (Exception ignored) {}

        releaseWakeLock();

        if (wasConnected) {
            notifyStatus("DISCONNECTED", "ارتباط SSH قطع شد.");
        }
    }

    @JavascriptInterface
    public boolean isConnected() {
        return isConnected.get();
    }

    @JavascriptInterface
    public void vibrate(int durationMs) {
        activity.runOnUiThread(() -> {
            try {
                Vibrator v = (Vibrator) activity.getSystemService(Context.VIBRATOR_SERVICE);
                if (v != null && v.hasVibrator()) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        v.vibrate(VibrationEffect.createOneShot(Math.min(durationMs, 500), VibrationEffect.DEFAULT_AMPLITUDE));
                    } else {
                        v.vibrate(Math.min(durationMs, 500));
                    }
                }
            } catch (Exception ignored) {}
        });
    }

    @JavascriptInterface
    public void copyToClipboard(String text) {
        activity.runOnUiThread(() -> {
            try {
                ClipboardManager clipboard = (ClipboardManager) activity.getSystemService(Context.CLIPBOARD_SERVICE);
                ClipData clip = ClipData.newPlainText("SSH Output", text);
                if (clipboard != null) {
                    clipboard.setPrimaryClip(clip);
                    toast("در کلیپ‌بورد کپی شد");
                }
            } catch (Exception e) {
                Log.e(TAG, "Clipboard copy error", e);
            }
        });
    }

    @JavascriptInterface
    public String getClipboardText() {
        try {
            ClipboardManager clipboard = (ClipboardManager) activity.getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard != null && clipboard.hasPrimaryClip()) {
                ClipData clip = clipboard.getPrimaryClip();
                if (clip != null && clip.getItemCount() > 0) {
                    CharSequence text = clip.getItemAt(0).getText();
                    return text != null ? text.toString() : "";
                }
            }
        } catch (Exception ignored) {}
        return "";
    }

    @JavascriptInterface
    public void toast(String message) {
        activity.runOnUiThread(() -> Toast.makeText(activity, message, Toast.LENGTH_SHORT).show());
    }

    @JavascriptInterface
    public void saveSessionProfiles(String profilesJson) {
        prefs.edit().putString(KEY_PROFILES, profilesJson).apply();
    }

    @JavascriptInterface
    public String getSavedSessionProfiles() {
        return prefs.getString(KEY_PROFILES, "[]");
    }

    @JavascriptInterface
    public void setKeepScreenOn(boolean keepOn) {
        if (keepOn) {
            acquireWakeLock();
        } else {
            releaseWakeLock();
        }
    }

    private void acquireWakeLock() {
        activity.runOnUiThread(() -> {
            try {
                if (wakeLock == null) {
                    PowerManager pm = (PowerManager) activity.getSystemService(Context.POWER_SERVICE);
                    if (pm != null) {
                        wakeLock = pm.newWakeLock(PowerManager.SCREEN_DIM_WAKE_LOCK, "RsshTerminal:WakeLock");
                    }
                }
                if (wakeLock != null && !wakeLock.isHeld()) {
                    wakeLock.acquire(4 * 60 * 60 * 1000L); // Max 4 hours
                }
            } catch (Exception ignored) {}
        });
    }

    private void releaseWakeLock() {
        activity.runOnUiThread(() -> {
            try {
                if (wakeLock != null && wakeLock.isHeld()) {
                    wakeLock.release();
                }
            } catch (Exception ignored) {}
        });
    }

    public void onDestroy() {
        cleanUp();
        executor.shutdownNow();
    }
}
