package org.rssh.chat;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.net.NetworkInfo;
import android.os.Build;
import android.os.Bundle;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.view.KeyEvent;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

public class MainActivity extends Activity {

    private WebView webView;
    private volatile boolean isForeground = false;

    @Override
    @SuppressLint({"SetJavaScriptEnabled", "JavascriptInterface"})
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // 1. Start persistent background service so connection remains active when screen locks
        try {
            Intent serviceIntent = new Intent(this, ChatForegroundService.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent);
            } else {
                startService(serviceIntent);
            }
        } catch (Exception ignored) {
        }

        // 2. Request Android 13+ Notification Runtime Permission
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, 101);
            }
        }

        // 3. Initialize WebView
        webView = new WebView(this);
        setContentView(webView);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setSupportZoom(false);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);

        // Allow mixed content for local HTTP / WS self-hosted servers
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);

        webView.setWebChromeClient(new WebChromeClient());
        webView.setWebViewClient(new WebViewClient());

        webView.addJavascriptInterface(new ChatNativeInterface(), "ChatNative");

        // Load web chat frontend bundled in APK assets
        webView.loadUrl("file:///android_asset/web/index.html");
    }

    @Override
    protected void onResume() {
        super.onResume();
        isForeground = true;
    }

    @Override
    protected void onPause() {
        super.onPause();
        isForeground = false;
    }

    public class ChatNativeInterface {

        @JavascriptInterface
        public void showToast(final String msg) {
            runOnUiThread(() -> Toast.makeText(MainActivity.this, msg, Toast.LENGTH_SHORT).show());
        }

        @JavascriptInterface
        public void vibrate(long milliseconds) {
            try {
                Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
                if (v != null && v.hasVibrator()) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        v.vibrate(VibrationEffect.createOneShot(milliseconds, VibrationEffect.DEFAULT_AMPLITUDE));
                    } else {
                        v.vibrate(milliseconds);
                    }
                }
            } catch (Exception ignored) {
            }
        }

        @JavascriptInterface
        public void copyToClipboard(final String text) {
            runOnUiThread(() -> {
                ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                if (clipboard != null) {
                    ClipData clip = ClipData.newPlainText("Chat message", text);
                    clipboard.setPrimaryClip(clip);
                    Toast.makeText(MainActivity.this, "Copied to clipboard", Toast.LENGTH_SHORT).show();
                }
            });
        }

        @JavascriptInterface
        public void showNotification(final String sender, final String message, final String room) {
            runOnUiThread(() -> ChatForegroundService.showIncomingMessageNotification(
                    MainActivity.this,
                    sender,
                    message,
                    room
            ));
        }

        @JavascriptInterface
        public boolean isAppForeground() {
            return isForeground;
        }

        @JavascriptInterface
        public void minimizeApp() {
            runOnUiThread(() -> moveTaskToBack(true));
        }

        @JavascriptInterface
        public void exitApp() {
            runOnUiThread(() -> {
                try {
                    stopService(new Intent(MainActivity.this, ChatForegroundService.class));
                } catch (Exception ignored) {
                }
                finishAndRemoveTask();
            });
        }

        @JavascriptInterface
        public boolean isNetworkConnected() {
            try {
                ConnectivityManager cm = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
                if (cm == null) return false;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    android.net.Network network = cm.getActiveNetwork();
                    if (network == null) return false;
                    NetworkCapabilities caps = cm.getNetworkCapabilities(network);
                    return caps != null && (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                                            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                                            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET));
                } else {
                    NetworkInfo info = cm.getActiveNetworkInfo();
                    return info != null && info.isConnected();
                }
            } catch (Exception e) {
                return true;
            }
        }

        @JavascriptInterface
        public String getAppVersion() {
            return "1.2.0";
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            // Check if web layer wants to close a modal or drawer first
            webView.evaluateJavascript("window.onBackPressed ? window.onBackPressed() : false;", value -> {
                if (!"true".equals(value)) {
                    // Minimize to background instead of destroying Activity
                    moveTaskToBack(true);
                }
            });
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }
}
