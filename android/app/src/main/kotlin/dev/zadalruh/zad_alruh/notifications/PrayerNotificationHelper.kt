package dev.zadalruh.zad_alruh.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import dev.zadalruh.zad_alruh.MainActivity
import dev.zadalruh.zad_alruh.alarm.AdhanVoiceRegistry
import dev.zadalruh.zad_alruh.alarm.CanonicalPrayer
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmReceiver
import java.util.zip.CRC32

object PrayerNotificationHelper {
    const val CHANNEL_ID_PLAYBACK_STATUS = "zad_alruh_adhan_playback_status"
    const val CHANNEL_ID_ALERT_ADAM = "zad_alruh_alert_adam"
    const val CHANNEL_ID_ALERT_ATCOVI = "zad_alruh_alert_atcovi"
    const val CHANNEL_ID_ALERT_MALMO_FAJR = "zad_alruh_alert_malmo_fajr"
    const val CHANNEL_ID_MANUAL_SILENT = "zad_alruh_prayer_manual_silent"

    const val NOTIFICATION_ID_MEDIA_PLAYBACK = 1001

    /**
     * Initializes all notification channels if they do not already exist.
     * Respects user modifications to existing channels.
     */
    fun ensureChannelsCreated(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return

        // 1. Silent playback status channel for mediaPlayback foreground service
        if (manager.getNotificationChannel(CHANNEL_ID_PLAYBACK_STATUS) == null) {
            val statusChannel = NotificationChannel(
                CHANNEL_ID_PLAYBACK_STATUS,
                "تشغيل الأذان",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "إشعار تشغيل الأذان في الخلفية"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            manager.createNotificationChannel(statusChannel)
        }

        // 2. Alert channel: Adam (General)
        ensureAlertChannel(
            context = context,
            manager = manager,
            channelId = CHANNEL_ID_ALERT_ADAM,
            channelName = "تنبيه الأذان (تسجيل عام)",
            rawSoundName = AdhanVoiceRegistry.RAW_ALERT_RESOURCE_NAMES[AdhanVoiceRegistry.VOICE_ADAM] ?: "adam_alert"
        )

        // 3. Alert channel: Atcovi
        ensureAlertChannel(
            context = context,
            manager = manager,
            channelId = CHANNEL_ID_ALERT_ATCOVI,
            channelName = "تنبيه الأذان (Atcovi)",
            rawSoundName = AdhanVoiceRegistry.RAW_ALERT_RESOURCE_NAMES[AdhanVoiceRegistry.VOICE_ATCOVI] ?: "atcovi_alert"
        )

        // 4. Alert channel: Malmo Fajr
        ensureAlertChannel(
            context = context,
            manager = manager,
            channelId = CHANNEL_ID_ALERT_MALMO_FAJR,
            channelName = "تنبيه أذان الفجر (مالمو)",
            rawSoundName = AdhanVoiceRegistry.RAW_ALERT_RESOURCE_NAMES[AdhanVoiceRegistry.VOICE_MALMO_FAJR] ?: "malmo_fajr_alert"
        )

        // 5. Dedicated silent notification channel for manual in-app playback lease
        if (manager.getNotificationChannel(CHANNEL_ID_MANUAL_SILENT) == null) {
            val silentChannel = NotificationChannel(
                CHANNEL_ID_MANUAL_SILENT,
                "تنبيه الصلاة أثناء الاستماع",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "إشعار تنبيه الصلاة بدون صوت أثناء الاستماع داخل التطبيق"
                setShowBadge(true)
                setSound(null, null)
                enableVibration(false)
            }
            manager.createNotificationChannel(silentChannel)
        }
    }

    private fun ensureAlertChannel(
        context: Context,
        manager: NotificationManager,
        channelId: String,
        channelName: String,
        rawSoundName: String
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (manager.getNotificationChannel(channelId) != null) {
            // Channel already exists; respect user's channel configuration without overwriting
            return
        }

        val soundUri = Uri.parse(
            "${ContentResolver.SCHEME_ANDROID_RESOURCE}://${context.packageName}/raw/$rawSoundName"
        )

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(
            channelId,
            channelName,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "تنبيهات مواعيد الصلاة"
            setSound(soundUri, audioAttributes)
            enableVibration(true)
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
    }

    fun getChannelIdForVoice(voiceId: String): String {
        return when (voiceId) {
            AdhanVoiceRegistry.VOICE_MALMO_FAJR -> CHANNEL_ID_ALERT_MALMO_FAJR
            AdhanVoiceRegistry.VOICE_ATCOVI -> CHANNEL_ID_ALERT_ATCOVI
            else -> CHANNEL_ID_ALERT_ADAM
        }
    }

    /**
     * Builds ongoing foreground status notification with a Stop action.
     */
    fun buildMediaPlaybackStatusNotification(
        context: Context,
        cityNameAr: String,
        prayerKey: String
    ): Notification {
        ensureChannelsCreated(context)
        val prayer = CanonicalPrayer.fromKey(prayerKey)
        val prayerName = prayer?.arabicName ?: prayerKey

        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val stopIntent = Intent(context, PrayerAlarmReceiver::class.java).apply {
            action = PrayerAlarmReceiver.ACTION_STOP_ACTIVE_ADHAN
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            context,
            1002,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val iconRes = getAppIcon(context)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID_PLAYBACK_STATUS)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder.setContentTitle("حان الآن وقت صلاة $prayerName")
            .setContentText("مدينة $cityNameAr")
            .setSmallIcon(iconRes)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(contentIntent)
            .addAction(
                Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(context, android.R.drawable.ic_media_pause),
                    "إيقاف",
                    stopPendingIntent
                ).build()
            )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setCategory(Notification.CATEGORY_SERVICE)
        }

        return builder.build()
    }

    /**
     * Posts a short alert notification for an event.
     */
    fun postShortAlertNotification(
        context: Context,
        eventKey: String,
        prayerKey: String,
        cityNameAr: String,
        voiceId: String
    ): Boolean {
        ensureChannelsCreated(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !manager.areNotificationsEnabled()) {
            return false
        }

        val channelId = getChannelIdForVoice(voiceId)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = manager.getNotificationChannel(channelId)
            if (channel != null && channel.importance == NotificationManager.IMPORTANCE_NONE) {
                return false
            }
        }

        val prayer = CanonicalPrayer.fromKey(prayerKey)
        val prayerName = prayer?.arabicName ?: prayerKey

        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val iconRes = getAppIcon(context)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder.setContentTitle("حان الآن وقت صلاة $prayerName")
            .setContentText("مدينة $cityNameAr")
            .setSmallIcon(iconRes)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setCategory(Notification.CATEGORY_EVENT)
        }

        val notificationId = getNotificationId(eventKey)
        manager.notify(notificationId, builder.build())
        return true
    }

    /**
     * Posts a dedicated silent notification when prayer is due during active manual playback.
     * Uses the dedicated low-importance, no-sound, no-vibration channel.
     * Text explains manual listening; no automatic audio is promised or replayed.
     */
    fun postSilentManualSuppressedNotification(
        context: Context,
        eventKey: String,
        prayerKey: String,
        cityNameAr: String
    ): Boolean {
        ensureChannelsCreated(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !manager.areNotificationsEnabled()) {
            return false
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = manager.getNotificationChannel(CHANNEL_ID_MANUAL_SILENT)
            if (channel != null && channel.importance == NotificationManager.IMPORTANCE_NONE) {
                return false
            }
        }

        val prayer = CanonicalPrayer.fromKey(prayerKey)
        val prayerName = prayer?.arabicName ?: prayerKey

        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val iconRes = getAppIcon(context)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID_MANUAL_SILENT)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder.setContentTitle("حان الآن وقت صلاة $prayerName")
            .setContentText("أثناء الاستماع داخل التطبيق يظهر تنبيه الصلاة بدون تشغيل صوت آخر؛ تشغيل الأذان التلقائي لا يعاد بعد انتهاء الاستماع.")
            .setSmallIcon(iconRes)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setCategory(Notification.CATEGORY_EVENT)
        }

        val notificationId = getNotificationId(eventKey)
        manager.notify(notificationId, builder.build())
        return true
    }

    fun cancelNotification(context: Context, notificationId: Int): Boolean {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return false
        return try {
            manager.cancel(notificationId)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun cancelEventNotification(context: Context, eventKey: String): Boolean {
        return cancelNotification(context, getNotificationId(eventKey))
    }

    private fun getAppIcon(context: Context): Int {
        val icon = context.applicationInfo.icon
        return if (icon != 0) icon else android.R.drawable.ic_lock_idle_alarm
    }

    fun isPlaybackStatusChannelBlocked(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return true
        val channel = manager.getNotificationChannel(CHANNEL_ID_PLAYBACK_STATUS) ?: return false
        return channel.importance == NotificationManager.IMPORTANCE_NONE
    }

    fun isVoiceChannelBlocked(context: Context, voiceId: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return true
        val channelId = getChannelIdForVoice(voiceId)
        val channel = manager.getNotificationChannel(channelId) ?: return false
        return channel.importance == NotificationManager.IMPORTANCE_NONE
    }

    fun isManualSilentChannelBlocked(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return true
        val channel = manager.getNotificationChannel(CHANNEL_ID_MANUAL_SILENT) ?: return false
        return channel.importance == NotificationManager.IMPORTANCE_NONE
    }

    fun isDndOrSilentActive(context: Context): Boolean {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
        if (audioManager != null) {
            if (audioManager.ringerMode == android.media.AudioManager.RINGER_MODE_SILENT ||
                audioManager.ringerMode == android.media.AudioManager.RINGER_MODE_VIBRATE
            ) {
                return true
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            if (nm != null) {
                val filter = nm.currentInterruptionFilter
                if (filter == NotificationManager.INTERRUPTION_FILTER_NONE ||
                    filter == NotificationManager.INTERRUPTION_FILTER_ALARMS
                ) {
                    return true
                }
            }
        }
        return false
    }

    fun getNotificationId(eventKey: String): Int {
        val crc = CRC32()
        crc.update(eventKey.toByteArray(Charsets.UTF_8))
        return (crc.value and 0x7FFFFFFF).toInt()
    }
}
