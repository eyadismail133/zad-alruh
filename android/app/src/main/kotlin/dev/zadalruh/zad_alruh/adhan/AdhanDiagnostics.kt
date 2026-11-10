package dev.zadalruh.zad_alruh.adhan

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Small on-device log of what happened at each prayer alarm (last 30 steps),
 * shown in Settings so a user can tell why the full adhan did not play.
 */
object AdhanDiagnostics {
    private const val PREFS = "zad_adhan_diagnostics"
    private const val KEY = "entries"
    private const val MAX = 30

    @Volatile
    var appContext: Context? = null

    @Synchronized
    fun record(context: Context?, eventKey: String, message: String) {
        val ctx = context?.applicationContext ?: appContext ?: return
        try {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = JSONArray(prefs.getString(KEY, "[]"))
            arr.put(JSONObject().apply {
                put("t", System.currentTimeMillis())
                put("e", eventKey)
                put("m", message)
            })
            val trimmed = JSONArray()
            val start = (arr.length() - MAX).coerceAtLeast(0)
            for (i in start until arr.length()) trimmed.put(arr.get(i))
            prefs.edit().putString(KEY, trimmed.toString()).apply()
        } catch (_: Exception) {}
    }

    fun read(context: Context): String = try {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "[]") ?: "[]"
    } catch (_: Exception) {
        "[]"
    }
}
