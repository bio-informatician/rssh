package org.rssh.chat;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.Color;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

public class ChatForegroundService extends Service {

    public static final String CHANNEL_SERVICE_ID = "rakhssh_bg_service_channel";
    public static final String CHANNEL_MESSAGES_ID = "rakhssh_messages_channel";
    public static final int SERVICE_NOTIFICATION_ID = 1001;

    private PowerManager.WakeLock wakeLock;
    private WifiManager.WifiLock wifiLock;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannels();
        acquireLocks();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startAsForegroundService();
        return START_STICKY;
    }

    private void startAsForegroundService() {
        Intent appIntent = new Intent(this, MainActivity.class);
        appIntent.setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this,
                0,
                appIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0)
        );

        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder = new Notification.Builder(this, CHANNEL_SERVICE_ID);
        } else {
            builder = new Notification.Builder(this);
            builder.setPriority(Notification.PRIORITY_MIN);
        }

        Notification notification = builder
                .setContentTitle("رخش چت (فعال در پس‌زمینه)")
                .setContentText("آماده دریافت پیام‌ها حتی هنگام قفل بودن صفحه")
                .setSmallIcon(R.drawable.ic_launcher)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build();

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(SERVICE_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(SERVICE_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
        } else {
            startForeground(SERVICE_NOTIFICATION_ID, notification);
        }
    }

    private void acquireLocks() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null && (wakeLock == null || !wakeLock.isHeld())) {
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "RakhsshChat::WakeLock");
                wakeLock.acquire();
            }
        } catch (Exception ignored) {
        }

        try {
            WifiManager wm = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            if (wm != null && (wifiLock == null || !wifiLock.isHeld())) {
                wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "RakhsshChat::WifiLock");
                wifiLock.acquire();
            }
        } catch (Exception ignored) {
        }
    }

    private void createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;

            // 1. Silent Ongoing Service Channel
            NotificationChannel serviceChannel = new NotificationChannel(
                    CHANNEL_SERVICE_ID,
                    "سرویس پس‌زمینه رخش چت",
                    NotificationManager.IMPORTANCE_LOW
            );
            serviceChannel.setDescription("فعال نگه داشتن برنامه جهت دریافت پیام در صفحه قفل");
            serviceChannel.setShowBadge(false);
            serviceChannel.setSound(null, null);
            serviceChannel.enableVibration(false);
            nm.createNotificationChannel(serviceChannel);

            // 2. High-Priority Message Notification Channel (Shows on Lock Screen)
            NotificationChannel messageChannel = new NotificationChannel(
                    CHANNEL_MESSAGES_ID,
                    "پیام‌های دریافتی رخش چت",
                    NotificationManager.IMPORTANCE_HIGH
            );
            messageChannel.setDescription("نمایش اعلان پیام‌های دریافتی جدید روی صفحه قفل");
            messageChannel.enableLights(true);
            messageChannel.setLightColor(Color.CYAN);
            messageChannel.enableVibration(true);
            messageChannel.setVibrationPattern(new long[]{0, 300, 120, 300});
            messageChannel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC); // Visible on Lock Screen

            Uri soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
            AudioAttributes audioAttributes = new AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                    .build();
            messageChannel.setSound(soundUri, audioAttributes);

            nm.createNotificationChannel(messageChannel);
        }
    }

    public static void showIncomingMessageNotification(Context context, String sender, String message, String room) {
        if (context == null) return;

        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return;

        Intent appIntent = new Intent(context, MainActivity.class);
        appIntent.setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                context,
                (int) System.currentTimeMillis(),
                appIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0)
        );

        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder = new Notification.Builder(context, CHANNEL_MESSAGES_ID);
        } else {
            builder = new Notification.Builder(context);
            builder.setPriority(Notification.PRIORITY_HIGH);
            builder.setDefaults(Notification.DEFAULT_ALL);
        }

        String title = sender != null && !sender.isEmpty() ? sender : "پیام جدید";
        if (room != null && !room.isEmpty()) {
            title += " («" + room + "»)";
        }

        builder.setContentTitle(title)
                .setContentText(message != null ? message : "")
                .setSmallIcon(R.drawable.ic_launcher)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setVisibility(Notification.VISIBILITY_PUBLIC) // Lock screen visibility
                .setCategory(Notification.CATEGORY_MESSAGE);

        int notifId = (int) (System.currentTimeMillis() % 100000);
        nm.notify(notifId, builder.build());
    }

    @Override
    public void onDestroy() {
        try {
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
            }
        } catch (Exception ignored) {
        }
        try {
            if (wifiLock != null && wifiLock.isHeld()) {
                wifiLock.release();
            }
        } catch (Exception ignored) {
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
