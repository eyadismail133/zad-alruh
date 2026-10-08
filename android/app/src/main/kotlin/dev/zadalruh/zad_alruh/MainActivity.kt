package dev.zadalruh.zad_alruh

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmCoordinator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL_PRAYER_ALARM = "dev.zadalruh.zad_alruh/prayer_alarm"
        private const val REQUEST_CODE_POST_NOTIFICATIONS = 5001
    }

    private var pendingNotificationResult: MethodChannel.Result? = null
    private var engineSessionId: String = java.util.UUID.randomUUID().toString()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val coordinator = PrayerAlarmCoordinator.initialize(applicationContext)

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
