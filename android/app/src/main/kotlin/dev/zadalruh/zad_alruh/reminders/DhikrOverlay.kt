package dev.zadalruh.zad_alruh.reminders

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import dev.zadalruh.zad_alruh.R
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Gentle on-screen dhikr reminders: a soft rounded card that floats over
 * whatever is on screen (top / center / bottom), fades in, and fades out by
 * itself — not a regular notification. Needs the "display over other apps"
 * permission; without it we fall back to a normal notification.
 */
object DhikrOverlay {
    private const val PREFS = "zad_dhikr_overlay"
    private const val KEY_ITEMS = "items"
    private const val KEY_POSITION = "position"
    private const val KEY_DURATION = "duration"
    private const val KEY_IDS = "scheduled_ids"
    private const val FALLBACK_CHANNEL = "zad_dhikr_overlay_fallback"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val MAX_ITEMS = 150

    private var current: View? = null

    fun canDraw(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    // ------------------------------------------------------------------
    // Scheduling
    // ------------------------------------------------------------------

    fun schedule(context: Context, items: JSONArray, position: String, durationSec: Int) {
        cancelAll(context)
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_ITEMS, items.toString())
            .putString(KEY_POSITION, position)
            .putInt(KEY_DURATION, durationSec)
            .apply()
        scheduleStored(context)
    }

    fun scheduleStored(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val items = try {
            JSONArray(prefs.getString(KEY_ITEMS, "[]"))
        } catch (_: Exception) {
            JSONArray()
        }
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        val ids = JSONArray()
        var count = 0
        for (i in 0 until items.length()) {
            if (count >= MAX_ITEMS) break
            val item = items.optJSONObject(i) ?: continue
            val at = item.optLong("at")
            if (at <= now) continue
            val id = item.optInt("id")
            val pi = pendingIntent(context, id, item.optString("title"), item.optString("body"))
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            ids.put(id)
            count++
        }
        prefs.edit().putString(KEY_IDS, ids.toString()).apply()
    }

    fun cancelAll(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = try {
            JSONArray(prefs.getString(KEY_IDS, "[]"))
        } catch (_: Exception) {
            JSONArray()
        }
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (i in 0 until ids.length()) {
            val pi = pendingIntent(context, ids.optInt(i), "", "")
            am.cancel(pi)
            pi.cancel()
        }
        prefs.edit().remove(KEY_IDS).remove(KEY_ITEMS).apply()
    }

    private fun pendingIntent(context: Context, id: Int, title: String, body: String): PendingIntent {
        val intent = Intent(context, DhikrOverlayReceiver::class.java).apply {
            action = "dev.zadalruh.zad_alruh.DHIKR_OVERLAY_$id"
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
        }
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    // ------------------------------------------------------------------
    // Display
    // ------------------------------------------------------------------

    fun deliver(context: Context, title: String, body: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val position = prefs.getString(KEY_POSITION, "top") ?: "top"
        val duration = prefs.getInt(KEY_DURATION, 8)
        if (canDraw(context)) {
            Handler(Looper.getMainLooper()).post {
                try {
                    show(context.applicationContext, title, body, position, duration)
                } catch (_: Exception) {
                    notifyFallback(context, title, body)
                }
            }
        } else {
            notifyFallback(context, title, body)
        }
    }

    fun show(context: Context, title: String, body: String, position: String, durationSec: Int) {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        current?.let { old ->
            try {
                wm.removeView(old)
            } catch (_: Exception) {}
            current = null
        }

        fun dp(v: Float) = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics
        ).toInt()

        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            setPadding(dp(22f), dp(16f), dp(22f), dp(18f))
            background = GradientDrawable(
                GradientDrawable.Orientation.TR_BL,
                intArrayOf(Color.parseColor("#0E5A52"), Color.parseColor("#1D7A6D"))
            ).apply { cornerRadius = dp(26f).toFloat() }
            elevation = dp(10f).toFloat()
            alpha = 0f
        }
        val header = TextView(context).apply {
            text = "$title  ·  زادُ الروح"
            setTextColor(Color.parseColor("#E3C27E"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.START
        }
        val message = TextView(context).apply {
            text = body
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.25f)
            setPadding(0, dp(8f), 0, dp(4f))
        }
        val hint = TextView(context).apply {
            text = "اضغط للإغلاق"
            setTextColor(Color.parseColor("#B3FFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            gravity = Gravity.CENTER
        }
        card.addView(header)
        card.addView(message)
        card.addView(hint)

        val container = FrameLayout(context).apply {
            setPadding(dp(16f), dp(12f), dp(16f), dp(12f))
            addView(card)
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = when (position) {
                "center" -> Gravity.CENTER
                "bottom" -> Gravity.BOTTOM
                else -> Gravity.TOP
            }
            y = when (position) {
                "bottom" -> dp(72f)
                "top" -> dp(36f)
                else -> 0
            }
        }

        val handler = Handler(Looper.getMainLooper())
        val dismiss = Runnable {
            card.animate().alpha(0f).translationY(
                if (position == "bottom") dp(24f).toFloat() else -dp(24f).toFloat()
            ).setDuration(350).withEndAction {
                try {
                    wm.removeView(container)
                } catch (_: Exception) {}
                if (current === container) current = null
            }.start()
        }
        card.setOnClickListener {
            handler.removeCallbacks(dismiss)
            dismiss.run()
        }

        wm.addView(container, params)
        current = container
        card.translationY = if (position == "bottom") dp(24f).toFloat() else -dp(24f).toFloat()
        card.animate().alpha(1f).translationY(0f).setDuration(450).start()
        handler.postDelayed(dismiss, durationSec.coerceIn(3, 60) * 1000L)
    }

    private fun notifyFallback(context: Context, title: String, body: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            nm.getNotificationChannel(FALLBACK_CHANNEL) == null
        ) {
            nm.createNotificationChannel(
                NotificationChannel(
                    FALLBACK_CHANNEL,
                    "تذكيرات الذكر",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
        }
        val n = NotificationCompat.Builder(context, FALLBACK_CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setTimeoutAfter(10 * 60 * 1000L)
            .build()
        try {
            nm.notify(71999, n)
        } catch (_: SecurityException) {}
    }
}

class DhikrOverlayReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra(DhikrOverlay.EXTRA_TITLE) ?: "ذكر"
        val body = intent.getStringExtra(DhikrOverlay.EXTRA_BODY) ?: return
        DhikrOverlay.deliver(context, title, body)
    }
}

class DhikrOverlayBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            DhikrOverlay.scheduleStored(context)
        } catch (_: Exception) {}
    }
}

/** MethodChannel "dev.zadalruh.zad_alruh/dhikr_overlay". */
object DhikrOverlayBridge {
    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "canDrawOverlays" -> result.success(DhikrOverlay.canDraw(context))
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:${context.packageName}")
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                    }
                    result.success(true)
                }
                "openAppInfo" -> {
                    // Android 13+/15: sideloaded apps must first "Allow restricted
                    // settings" from App info's ⋮ menu before the overlay toggle works.
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:${context.packageName}")
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    result.success(true)
                }
                "schedule" -> {
                    val raw = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                    val arr = JSONArray()
                    for (m in raw) {
                        arr.put(JSONObject().apply {
                            put("id", (m["id"] as Number).toInt())
                            put("at", (m["at"] as Number).toLong())
                            put("title", m["title"] as? String ?: "")
                            put("body", m["body"] as? String ?: "")
                        })
                    }
                    DhikrOverlay.schedule(
                        context.applicationContext,
                        arr,
                        call.argument<String>("position") ?: "top",
                        call.argument<Int>("duration") ?: 8
                    )
                    result.success(true)
                }
                "cancelAll" -> {
                    DhikrOverlay.cancelAll(context.applicationContext)
                    result.success(true)
                }
                "preview" -> {
                    if (!DhikrOverlay.canDraw(context)) {
                        result.success(false)
                        return
                    }
                    DhikrOverlay.show(
                        context.applicationContext,
                        call.argument<String>("title") ?: "ذكر",
                        call.argument<String>("body") ?: "سبحان الله",
                        call.argument<String>("position") ?: "top",
                        call.argument<Int>("duration") ?: 8
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("overlay_error", e.message, null)
        }
    }
}
