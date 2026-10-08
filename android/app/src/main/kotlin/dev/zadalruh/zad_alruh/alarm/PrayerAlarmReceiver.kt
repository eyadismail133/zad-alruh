package dev.zadalruh.zad_alruh.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.zadalruh.zad_alruh.adhan.AdhanMediaPlaybackService

/**
 * BroadcastReceiver triggered by AlarmManager for exact and companion prayer alarms,
 * as well as user notification actions (e.g. Stop adhan playback).
 */
class PrayerAlarmReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_PRAYER_ALARM = "dev.zadalruh.zad_alruh.action.PRAYER_ALARM"
        const val ACTION_STOP_ACTIVE_ADHAN = "dev.zadalruh.zad_alruh.action.STOP_ACTIVE_ADHAN"

        const val EXTRA_EVENT_KEY = "extra_event_key"
        const val EXTRA_GENERATION_TOKEN = "extra_generation_token"
        const val EXTRA_ALARM_TYPE = "extra_alarm_type"
        const val EXTRA_TRIGGER_TIME = "extra_trigger_time"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        when (intent.action) {
            ACTION_STOP_ACTIVE_ADHAN -> {
                AdhanMediaPlaybackService.stopActiveInstance()
            }
            ACTION_PRAYER_ALARM -> {
                val eventKey = intent.getStringExtra(EXTRA_EVENT_KEY) ?: return
                val token = intent.getLongExtra(EXTRA_GENERATION_TOKEN, -1L)
                val alarmTypeRaw = intent.getStringExtra(EXTRA_ALARM_TYPE) ?: AlarmTriggerType.COMPANION.key
                val alarmType = AlarmTriggerType.fromKey(alarmTypeRaw)

                if (token < 0) return

                val coordinator = PrayerAlarmCoordinator.initialize(context)
                coordinator.handleAlarmTrigger(
                    eventKey = eventKey,
                    token = token,
                    alarmType = alarmType
                )
            }
        }
    }
}
