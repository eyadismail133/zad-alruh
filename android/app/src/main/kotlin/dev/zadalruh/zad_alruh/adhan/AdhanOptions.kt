package dev.zadalruh.zad_alruh.adhan

import android.content.Context

/** User options for prayer-time adhan playback (set from Flutter settings). */
object AdhanOptions {
    private const val PREFS = "zad_adhan_options"
    private const val KEY_PLAY_WHEN_SILENT = "play_when_silent"

    fun playWhenSilent(context: Context): Boolean = try {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_PLAY_WHEN_SILENT, true)
    } catch (_: Exception) {
        true
    }

    fun setPlayWhenSilent(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_PLAY_WHEN_SILENT, value).apply()
    }
}
