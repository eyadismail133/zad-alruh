package dev.zadalruh.zad_alruh.adhan

import android.content.Context
import java.io.File

/**
 * Optional user-downloaded adhan recordings (see Flutter OnlineAdhanStore).
 * Paths point into the app's private storage; when a file is missing the
 * bundled voice from the prayer plan is used instead.
 */
object CustomAdhanFiles {
    const val FILE_PREFIX = "file://"
    private const val PREFS = "zad_custom_adhan"
    private const val KEY_GENERAL = "general_path"
    private const val KEY_FAJR = "fajr_path"

    fun save(context: Context, general: String?, fajr: String?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_GENERAL, general)
            .putString(KEY_FAJR, fajr)
            .apply()
    }

    /** Returns "file://<path>" for the prayer, or null to use bundled audio. */
    fun resolve(context: Context, prayerKey: String): String? {
        return try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val key = if (prayerKey == "fajr") KEY_FAJR else KEY_GENERAL
            val path = prefs.getString(key, null) ?: return null
            val file = File(path)
            if (file.isFile && file.length() > 10 * 1024) FILE_PREFIX + path else null
        } catch (_: Exception) {
            null
        }
    }
}
