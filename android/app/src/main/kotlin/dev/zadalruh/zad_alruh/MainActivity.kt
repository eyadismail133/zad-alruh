package dev.zadalruh.zad_alruh

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmCoordinator
import dev.zadalruh.zad_alruh.adhan.CustomAdhanFiles
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import dev.zadalruh.zad_alruh.qibla.CompassStreamHandler
import dev.zadalruh.zad_alruh.reminders.DhikrOverlayBridge

class MainActivity : AudioServiceActivity() {

    companion object {
        const val CHANNEL_PRAYER_ALARM = "dev.zadalruh.zad_alruh/prayer_alarm"
        private const val REQUEST_CODE_POST_NOTIFICATIONS = 5001
    }

    private var pendingNotificationResult: MethodChannel.Result? = null
    private var engineSessionId: String = java.util.UUID.randomUUID().toString()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val coordinator = PrayerAlarmCoordinator.initialize(applicationContext)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.zadalruh.zad_alruh/compass"
        ).setStreamHandler(CompassStreamHandler(this))

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.zadalruh.zad_alruh/dhikr_overlay"
        ).setMethodCallHandler { call, result ->
            DhikrOverlayBridge.handle(this, call, result)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_PRAYER_ALARM
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAuthorizationToken" -> {
                    try {
                        val token = coordinator.store.getGenerationToken()
                        result.success(mapOf("token" to token))
                    } catch (e: Exception) {
                        result.success(
                            mapOf(
                                "success" to false,
                                "errorCode" to "INTERNAL_ERROR",
                                "messageAr" to "تعذر قراءة رمز التفويض الحالي."
                            )
                        )
                    }
                }
                "replacePlan" -> {
                    val arguments = call.arguments as? Map<*, *>
                    if (arguments == null) {
                        result.success(
                            mapOf(
                                "success" to false,
                                "errorCode" to "INVALID_ARGUMENTS",
                                "messageAr" to "بيانات خطة مواعيد الصلاة غير متوفرة."
                            )
                        )
                    } else {
                        val res = coordinator.replacePlan(arguments)
                        result.success(res)
                    }
                }
                "scheduleTestAdhan" -> {
                    val seconds = call.argument<Int>("seconds") ?: 30
                    val am = getSystemService(android.content.Context.ALARM_SERVICE) as android.app.AlarmManager
                    val pi = android.app.PendingIntent.getBroadcast(
                        applicationContext,
                        991_001,
                        Intent(applicationContext, dev.zadalruh.zad_alruh.alarm.PrayerAlarmReceiver::class.java)
                            .setAction(dev.zadalruh.zad_alruh.alarm.PrayerAlarmReceiver.ACTION_TEST_ADHAN),
                        android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
                    )
                    val at = System.currentTimeMillis() + seconds * 1000L
                    try {
                        am.setAlarmClock(android.app.AlarmManager.AlarmClockInfo(at, null), pi)
                        dev.zadalruh.zad_alruh.adhan.AdhanDiagnostics.record(applicationContext, "test", "test scheduled in ${seconds}s")
                        result.success(true)
                    } catch (e: Exception) {
                        dev.zadalruh.zad_alruh.adhan.AdhanDiagnostics.record(applicationContext, "test", "schedule_failed: ${e.javaClass.simpleName}")
                        result.success(false)
                    }
                }
                "getAdhanDiagnostics" -> {
                    val pm = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
                    val am = getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
                    result.success(
                        mapOf(
                            "log" to dev.zadalruh.zad_alruh.adhan.AdhanDiagnostics.read(applicationContext),
                            "ignoringBattery" to pm.isIgnoringBatteryOptimizations(packageName),
                            "alarmVolume" to am.getStreamVolume(android.media.AudioManager.STREAM_ALARM),
                            "alarmVolumeMax" to am.getStreamMaxVolume(android.media.AudioManager.STREAM_ALARM)
                        )
                    )
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                .setData(Uri.parse("package:$packageName"))
                        )
                    } catch (_: Exception) {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    }
                    result.success(true)
                }
                "setAdhanOptions" -> {
                    call.argument<Boolean>("playWhenSilent")?.let {
                        dev.zadalruh.zad_alruh.adhan.AdhanOptions.setPlayWhenSilent(applicationContext, it)
                    }
                    result.success(true)
                }
                "setCustomAdhanFiles" -> {
                    CustomAdhanFiles.save(
                        applicationContext,
                        general = call.argument<String>("general"),
                        fajr = call.argument<String>("fajr")
                    )
                    result.success(true)
                }
                "disableAlarms" -> {
                    val res = coordinator.disableAlarms()
                    result.success(res)
                }
                "resetAll" -> {
                    val res = coordinator.resetAll()
                    result.success(res)
                }
                "getState" -> {
                    val state = coordinator.getState()
                    result.success(state)
                }
                "acquireManualPlaybackLease" -> {
                    val requestId = (call.arguments as? Map<*, *>)?.get("requestId") as? String
                        ?: (call.arguments as? String)
                    val res = coordinator.acquireManualPlaybackLease(requestId, engineSessionId)
                    result.success(res)
                }
                "releaseManualPlaybackLease" -> {
                    val leaseToken = (call.arguments as? Map<*, *>)?.get("leaseToken") as? String
                        ?: (call.arguments as? String)
                    val res = coordinator.releaseManualPlaybackLease(leaseToken)
                    result.success(res)
                }
                "stopActivePlayback" -> {
                    val wasStopped = coordinator.stopActiveAdhanPlayback()
                    result.success(mapOf("stopped" to wasStopped))
                }
                "canScheduleExactAlarms" -> {
                    val canExact = coordinator.getState()["canScheduleExactAlarms"] as? Boolean ?: false
                    result.success(canExact)
                }
                "canPostNotifications" -> {
                    val allowed = coordinator.getState()["notificationsAllowed"] as? Boolean ?: false
                    result.success(allowed)
                }
                "requestExactAlarmPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        if (ActivityCompat.checkSelfPermission(
                                this,
                                Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(true)
                        } else {
                            // Prevent overwriting pending result on duplicate request:
                            val existing = pendingNotificationResult
                            if (existing != null) {
                                existing.success(false)
                                pendingNotificationResult = null
                            }
                            pendingNotificationResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQUEST_CODE_POST_NOTIFICATIONS
                            )
                        }
                    } else {
                        result.success(true)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pendingNotificationResult?.let {
            it.success(false)
            pendingNotificationResult = null
        }
        // Engine detach alone is NOT confirmed silence; preserve suppression if lifecycle callback
        // cannot confirm player retirement. Do not prematurely clear active manual playback lease.
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationResult?.success(granted)
            pendingNotificationResult = null
        }
    }
}
