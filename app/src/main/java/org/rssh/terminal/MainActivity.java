package org.rssh.terminal;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.res.Configuration;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class MainActivity extends Activity {
    private WebView webView;
    private SshBridge sshBridge;

    @SuppressLint({"SetJavaScriptEnabled", "JavascriptInterface"})
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Keep status bar and navigation bar dark
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
        getWindow().setStatusBarColor(Color.parseColor("#111827"));
        getWindow().setNavigationBarColor(Color.parseColor("#05080f"));

        webView = new WebView(this);
        webView.setBackgroundColor(Color.parseColor("#0a0e17"));
        setContentView(webView);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        settings.setSupportZoom(true);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);

        sshBridge = new SshBridge(this, webView);
        webView.addJavascriptInterface(sshBridge, "AndroidSSH");

        webView.setWebChromeClient(new WebChromeClient());
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return false;
            }
        });

        webView.loadUrl("file:///android_asset/web/index.html");
    }

    @Override
    public void onBackPressed() {
        if (sshBridge != null && sshBridge.isConnected()) {
            new AlertDialog.Builder(this)
                .setTitle("قطع اتصال SSH؟")
                .setMessage("آیا می‌خواهید نشست فعال ترمینال را ببندید؟")
                .setPositiveButton("بله، قطع اتصال", (dialog, which) -> {
                    sshBridge.disconnect();
                    super.onBackPressed();
                })
                .setNegativeButton("انصراف", null)
                .show();
        } else {
            // Check if modal is open in JS
            webView.evaluateJavascript("window.onBackPressed ? window.onBackPressed() : false;", value -> {
                if ("false".equals(value) || "null".equals(value)) {
                    super.onBackPressed();
                }
            });
        }
    }

    @Override
    protected void onDestroy() {
        if (sshBridge != null) {
            sshBridge.onDestroy();
        }
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }
}
