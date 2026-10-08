package dev.zadalruh.zad_alruh.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * BroadcastReceiver for restoring saved future prayer alarms after device reboot,
 * application updates, and system time/timezone changes.
 * Strictly restores FUTURE alarms only; never plays sound or launches background service.
 */
class PrayerBootReceiver : BroadcastReceiver() {

    companion object {
        private val SUPPORTED_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED
        )
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        val action = intent.action ?: return

        if (!SUPPORTED_ACTIONS.contains(action)) return

        val coordinator = PrayerAlarmCoordinator.initialize(context)
        coordinator.restoreScheduleOnBootOrTimeChange()
    }
}
