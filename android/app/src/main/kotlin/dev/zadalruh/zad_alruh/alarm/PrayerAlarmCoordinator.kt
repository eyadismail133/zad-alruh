package dev.zadalruh.zad_alruh.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat
import dev.zadalruh.zad_alruh.adhan.AdhanMediaPlaybackService
import dev.zadalruh.zad_alruh.notifications.PrayerNotificationHelper
import java.io.File
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Pluggable OS boundaries allowing 100% JVM-runnable testing of real state transitions.
 */
interface TimeProvider {
    fun now(): Long
}

class SystemTimeProvider : TimeProvider {
    override fun now(): Long = System.currentTimeMillis()
}

interface AlarmSchedulerGateway {
    fun canScheduleExactAlarms(): Boolean
    fun scheduleExact(eventKey: String, triggerEpochMillis: Long, token: Long, requestCode: Int): Boolean
    fun scheduleCompanion(eventKey: String, triggerEpochMillis: Long, token: Long, requestCode: Int): Boolean
    fun cancelAlarms(event: PrayerEventRecord): Boolean
}

interface NotificationGateway {
    fun areNotificationsEnabled(): Boolean
    fun isPlaybackStatusChannelBlocked(): Boolean
    fun isVoiceChannelBlocked(voiceId: String): Boolean
    fun isManualSilentChannelBlocked(): Boolean
    fun isDndOrSilentActive(): Boolean
    fun postShortAlert(
        eventKey: String,
        prayerKey: String,
        cityNameAr: String,
        voiceId: String
    ): Boolean
    fun postSilentManualSuppressedAlert(
        eventKey: String,
        prayerKey: String,
        cityNameAr: String
    ): Boolean
    fun cancelEventNotification(eventKey: String): Boolean
}

interface ServiceGateway {
    fun isServiceRunning(): Boolean
    fun startAdhanPlaybackService(eventKey: String, token: Long): Boolean
    fun stopAdhanPlaybackService(): Boolean
}

/**
 * Production Android AlarmManager implementation.
 */
class AndroidAlarmScheduler(private val context: Context) : AlarmSchedulerGateway {
    private val alarmManager: AlarmManager?
        get() = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager

    override fun canScheduleExactAlarms(): Boolean {
        val am = alarmManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.canScheduleExactAlarms()
        } else {
            true
        }
    }

    override fun scheduleExact(
        eventKey: String,
        triggerEpochMillis: Long,
        token: Long,
        requestCode: Int
    ): Boolean {
        val am = alarmManager ?: return false
        val intent = Intent(context, PrayerAlarmReceiver::class.java).apply {
            action = PrayerAlarmReceiver.ACTION_PRAYER_ALARM
            putExtra(PrayerAlarmReceiver.EXTRA_EVENT_KEY, eventKey)
            putExtra(PrayerAlarmReceiver.EXTRA_GENERATION_TOKEN, token)
            putExtra(PrayerAlarmReceiver.EXTRA_ALARM_TYPE, AlarmTriggerType.EXACT.key)
            putExtra(PrayerAlarmReceiver.EXTRA_TRIGGER_TIME, triggerEpochMillis)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerEpochMillis, pendingIntent)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, triggerEpochMillis, pendingIntent)
            }
            true
        } catch (_: SecurityException) {
            try {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerEpochMillis, pendingIntent)
                true
            } catch (_: Exception) {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    override fun scheduleCompanion(
        eventKey: String,
        triggerEpochMillis: Long,
        token: Long,
        requestCode: Int
    ): Boolean {
        val am = alarmManager ?: return false
        val intent = Intent(context, PrayerAlarmReceiver::class.java).apply {
            action = PrayerAlarmReceiver.ACTION_PRAYER_ALARM
            putExtra(PrayerAlarmReceiver.EXTRA_EVENT_KEY, eventKey)
            putExtra(PrayerAlarmReceiver.EXTRA_GENERATION_TOKEN, token)
            putExtra(PrayerAlarmReceiver.EXTRA_ALARM_TYPE, AlarmTriggerType.COMPANION.key)
            putExtra(PrayerAlarmReceiver.EXTRA_TRIGGER_TIME, triggerEpochMillis)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerEpochMillis, pendingIntent)
            } else {
                am.set(AlarmManager.RTC_WAKEUP, triggerEpochMillis, pendingIntent)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun cancelAlarms(event: PrayerEventRecord): Boolean {
        val am = alarmManager ?: return false
        var success = true

        try {
            val exactIntent = Intent(context, PrayerAlarmReceiver::class.java).apply {
                action = PrayerAlarmReceiver.ACTION_PRAYER_ALARM
            }
            val exactPendingIntent = PendingIntent.getBroadcast(
                context,
                event.getPendingIntentRequestCode(AlarmTriggerType.EXACT),
                exactIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE
            )
            if (exactPendingIntent != null) {
                am.cancel(exactPendingIntent)
                exactPendingIntent.cancel()
            }
        } catch (_: Exception) {
            success = false
        }

        try {
            val companionIntent = Intent(context, PrayerAlarmReceiver::class.java).apply {
                action = PrayerAlarmReceiver.ACTION_PRAYER_ALARM
            }
            val companionPendingIntent = PendingIntent.getBroadcast(
                context,
                event.getPendingIntentRequestCode(AlarmTriggerType.COMPANION),
                companionIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE
            )
            if (companionPendingIntent != null) {
                am.cancel(companionPendingIntent)
                companionPendingIntent.cancel()
            }
        } catch (_: Exception) {
            success = false
        }

        return success
    }
}

/**
 * Production Android notification gateway.
 */
class AndroidNotificationGateway(private val context: Context) : NotificationGateway {
    override fun areNotificationsEnabled(): Boolean {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
            ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            nm.areNotificationsEnabled()
        } else {
            true
        }
    }

    override fun isPlaybackStatusChannelBlocked(): Boolean {
        return PrayerNotificationHelper.isPlaybackStatusChannelBlocked(context)
    }

    override fun isVoiceChannelBlocked(voiceId: String): Boolean {
        return PrayerNotificationHelper.isVoiceChannelBlocked(context, voiceId)
    }

    override fun isManualSilentChannelBlocked(): Boolean {
        return PrayerNotificationHelper.isManualSilentChannelBlocked(context)
    }

    override fun isDndOrSilentActive(): Boolean {
        return PrayerNotificationHelper.isDndOrSilentActive(context)
    }

    override fun postShortAlert(
        eventKey: String,
        prayerKey: String,
        cityNameAr: String,
        voiceId: String
    ): Boolean {
        return PrayerNotificationHelper.postShortAlertNotification(
            context = context,
            eventKey = eventKey,
            prayerKey = prayerKey,
            cityNameAr = cityNameAr,
            voiceId = voiceId
        )
    }

    override fun postSilentManualSuppressedAlert(
        eventKey: String,
        prayerKey: String,
        cityNameAr: String
    ): Boolean {
        return PrayerNotificationHelper.postSilentManualSuppressedNotification(
            context = context,
            eventKey = eventKey,
            prayerKey = prayerKey,
            cityNameAr = cityNameAr
        )
    }

    override fun cancelEventNotification(eventKey: String): Boolean {
        return try {
            PrayerNotificationHelper.cancelEventNotification(context, eventKey)
        } catch (_: Exception) {
            false
        }
    }
}

/**
 * Production Android service gateway.
 */
class AndroidServiceGateway(private val context: Context) : ServiceGateway {
    override fun isServiceRunning(): Boolean = AdhanMediaPlaybackService.isRunning

    override fun startAdhanPlaybackService(eventKey: String, token: Long): Boolean {
        return try {
            val intent = Intent(context, AdhanMediaPlaybackService::class.java).apply {
                action = AdhanMediaPlaybackService.ACTION_START_ADHAN
                putExtra(AdhanMediaPlaybackService.EXTRA_EVENT_KEY, eventKey)
                putExtra(AdhanMediaPlaybackService.EXTRA_GENERATION_TOKEN, token)
            }
            ContextCompat.startForegroundService(context, intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun stopAdhanPlaybackService(): Boolean {
        return AdhanMediaPlaybackService.stopActiveInstance()
    }
}

/**
 * In-memory representation of an active process-local manual playback lease.
 */
data class ManualPlaybackLease(
    val sessionId: String,
    val requestId: String,
    val leaseToken: String,
    val acquiredEpochMillis: Long
)

/**
 * Central coordinator singleton for native Android prayer alarms.
 */
class PrayerAlarmCoordinator(
    val store: PrayerAlarmStore,
    val timeProvider: TimeProvider,
    private val alarmScheduler: AlarmSchedulerGateway,
    private val notificationGateway: NotificationGateway,
    private val serviceGateway: ServiceGateway
) {
    val stateMachine = PrayerDeliveryStateMachine(store)
    private val coordinatorLock = ReentrantLock()

    @Volatile
    private var currentManualLease: ManualPlaybackLease? = null
    private val postedOwnedNotificationKeys = mutableSetOf<String>()

    fun isManualPlaybackLeaseActive(): Boolean = currentManualLease != null

    fun getManualPlaybackLease(): ManualPlaybackLease? = currentManualLease

    private fun getOwnedEventNotificationKeysToCancel(): Set<String> {
        val keys = mutableSetOf<String>()
        keys.addAll(postedOwnedNotificationKeys)
        val ledger = store.getConsumedLedgerSnapshot()
        for ((key, record) in ledger) {
            if (record.state == DeliveryState.SHORT_DELIVERED) {
                keys.add(key)
            }
        }
        store.getActivePlan()?.events?.forEach { ev ->
            if (ledger[ev.eventKey]?.state == DeliveryState.SHORT_DELIVERED) {
                keys.add(ev.eventKey)
            }
        }
        return keys
    }

    private fun cancelOwnedEventNotificationsUnderLock(): Boolean {
        val keysToCancel = getOwnedEventNotificationKeysToCancel()
        for (key in keysToCancel) {
            val cancelled = notificationGateway.cancelEventNotification(key)
            if (!cancelled) {
                return false
            }
            postedOwnedNotificationKeys.remove(key)
        }
        return true
    }

    /**
     * Acquires a process-local manual playback lease under the shared coordinatorLock.
     * Validates requestId bounded nonblank, confirms native service stop, and grants
     * an opaque matching token only on confirmed stop.
     * Existing live owner lease must not be overwritten just because a new request arrived;
     * rejects busy except genuine idempotent same-session same-requestId.
     */
    fun acquireManualPlaybackLease(
        requestId: String?,
        engineSessionId: String
    ): Map<String, Any?> = coordinatorLock.withLock {
        if (requestId == null || requestId.isBlank() || requestId.length > 256) {
            return mapOf(
                "acquired" to false,
                "errorCode" to "INVALID_REQUEST_ID",
                "messageAr" to "معرّف طلب التشغيل اليدوي غير صالح."
            )
        }

        val existing = currentManualLease
        if (existing != null) {
            // Idempotent retry for the exact same session and requestId
            if (existing.sessionId == engineSessionId && existing.requestId == requestId) {
                return mapOf(
                    "acquired" to true,
                    "leaseToken" to existing.leaseToken,
                    "idempotent" to true
                )
            }
            // Existing live owner lease must not be overwritten
            return mapOf(
                "acquired" to false,
                "errorCode" to "LEASE_BUSY",
                "messageAr" to "يوجد إذن تشغيل يدوي نشط حالياً لم يتم تحريره."
            )
        }

        // 1. Confirm native adhan service stop before granting lease
        val stopped = serviceGateway.stopAdhanPlaybackService()
        if (!stopped) {
            return mapOf(
                "acquired" to false,
                "errorCode" to "NATIVE_SERVICE_STOP_FAILED",
                "messageAr" to "تعذر تأكيد إيقاف تشغيل الأذان النشط."
            )
        }

        // 2. Cancel existing owned prayer event notifications before granting lease
        val notificationsCancelled = cancelOwnedEventNotificationsUnderLock()
        if (!notificationsCancelled) {
            return mapOf(
                "acquired" to false,
                "errorCode" to "NOTIFICATION_CANCEL_FAILED",
                "messageAr" to "تعذر تأكيد إلغاء تنبيهات الصلاة النشطة."
            )
        }

        val leaseToken = "lease_" + java.util.UUID.randomUUID().toString()
        currentManualLease = ManualPlaybackLease(
            sessionId = engineSessionId,
            requestId = requestId,
            leaseToken = leaseToken,
            acquiredEpochMillis = timeProvider.now()
        )

        return mapOf(
            "acquired" to true,
            "leaseToken" to leaseToken
        )
    }

    /**
     * Releases the current manual playback lease under coordinatorLock.
     * Clears ONLY if leaseToken matches current lease.
     * Stale token release is harmless and does not clear current replacement lease.
     * No automatic replay on release.
     */
    fun releaseManualPlaybackLease(leaseToken: String?): Map<String, Any?> = coordinatorLock.withLock {
        if (leaseToken.isNullOrBlank()) {
            return mapOf(
                "released" to true,
                "cleared" to false,
                "reason" to "blank_token"
            )
        }

        val existing = currentManualLease
        if (existing == null) {
            return mapOf(
                "released" to true,
                "cleared" to false,
                "reason" to "no_active_lease"
            )
        }

        if (existing.leaseToken != leaseToken) {
            // Stale or mismatched token: harmless no-op, do NOT clear current replacement lease!
            return mapOf(
                "released" to true,
                "cleared" to false,
                "reason" to "token_mismatch"
            )
        }

        currentManualLease = null
        return mapOf(
            "released" to true,
            "cleared" to true
        )
    }

    companion object {
        const val COMPANION_OFFSET_WHEN_EXACT_ALLOWED_MILLIS = 45_000L // 45 seconds

        @Volatile
        private var customInstance: PrayerAlarmCoordinator? = null

        val instance: PrayerAlarmCoordinator
            get() = customInstance ?: error("PrayerAlarmCoordinator must be initialized with Context")

        fun initialize(context: Context): PrayerAlarmCoordinator {
            val existing = customInstance
            if (existing != null) return existing

            synchronized(this) {
                val doubleCheck = customInstance
                if (doubleCheck != null) return doubleCheck

                PrayerNotificationHelper.ensureChannelsCreated(context)

                val file = File(context.filesDir, "zad_alruh_prayer_alarm_store.json")
                val driver = FileStorageDriver(file)
                val store = PrayerAlarmStore(driver)
                val created = PrayerAlarmCoordinator(
                    store = store,
                    timeProvider = SystemTimeProvider(),
                    alarmScheduler = AndroidAlarmScheduler(context),
                    notificationGateway = AndroidNotificationGateway(context),
                    serviceGateway = AndroidServiceGateway(context)
                )
                customInstance = created
                return created
            }
        }

        fun setTestInstance(coordinator: PrayerAlarmCoordinator) {
            customInstance = coordinator
        }
    }

    /**
     * Replaces the current schedule plan atomically.
     * Enforces Validate + CAS first: old alarms are only cancelled after CAS success,
     * ensuring that stale calls or persistence failures have zero active OS side effects.
     */
    fun replacePlan(rawPlanMap: Map<*, *>): Map<String, Any?> = coordinatorLock.withLock {
        val now = timeProvider.now()
        val validation = PrayerPlanValidator.validate(rawPlanMap, now)
        if (validation is PlanValidationResult.Invalid) {
            return mapOf(
                "success" to false,
                "errorCode" to validation.errorCode,
                "messageAr" to validation.messageAr,
                "detail" to validation.detail
            )
        }

        val plan = (validation as PlanValidationResult.Valid).plan

        // 1. Validate + CAS FIRST (do NOT cancel old alarms before CAS succeeds!)
        val oldPlan = store.getActivePlan()
        val replaceResult = store.replacePlan(plan.expectedToken, plan, now)

        when (replaceResult) {
            is ReplacePlanResult.StaleToken -> {
                return mapOf(
                    "success" to false,
                    "errorCode" to "STALE_AUTHORIZATION_TOKEN",
                    "messageAr" to "انتهت صلاحية رمز التفويض، يرجى إعادة محاولة جدولة المواعيد.",
                    "currentToken" to replaceResult.currentToken
                )
            }
            is ReplacePlanResult.PersistenceFailure -> {
                return mapOf(
                    "success" to false,
                    "errorCode" to "STORAGE_PERSISTENCE_FAILURE",
                    "messageAr" to replaceResult.messageAr
                )
            }
            is ReplacePlanResult.Success -> {
                // 2. CAS succeeded! Now cancel old alarms:
                var oldCancelFailed = false
                if (oldPlan != null) {
                    for (ev in oldPlan.events) {
                        val cancelled = alarmScheduler.cancelAlarms(ev)
                        if (!cancelled) {
                            oldCancelFailed = true
                        }
                    }
                }

                // 3. Schedule new alarms:
                val canExact = alarmScheduler.canScheduleExactAlarms()
                var attemptedEventsCount = 0
                var exactScheduledCount = 0
                var companionScheduledCount = 0
                var schedulingIncomplete = false
                val ledger = store.getConsumedLedgerSnapshot()

                for (event in plan.events) {
                    val record = ledger[event.eventKey]
                    // Do not schedule if already consumed for same city/date/prayer
                    if (record != null && record.state.isTerminal) {
                        continue
                    }

                    if (event.triggerEpochMillis > now) {
                        attemptedEventsCount++
                        val exactCode = event.getPendingIntentRequestCode(AlarmTriggerType.EXACT)
                        val compCode = event.getPendingIntentRequestCode(AlarmTriggerType.COMPANION)

                        if (canExact) {
                            val exactOk = alarmScheduler.scheduleExact(
                                event.eventKey,
                                event.triggerEpochMillis,
                                replaceResult.newToken,
                                exactCode
                            )
                            if (exactOk) {
                                exactScheduledCount++
                            } else {
                                schedulingIncomplete = true
                            }

                            // Offset companion alarm by 45s when exact is enabled
                            val compOk = alarmScheduler.scheduleCompanion(
                                event.eventKey,
                                event.triggerEpochMillis + COMPANION_OFFSET_WHEN_EXACT_ALLOWED_MILLIS,
                                replaceResult.newToken,
                                compCode
                            )
                            if (compOk) {
                                companionScheduledCount++
                            } else {
                                schedulingIncomplete = true
                            }
                        } else {
                            // Inexact companion fallback at event instant when exact is denied
                            val compOk = alarmScheduler.scheduleCompanion(
                                event.eventKey,
                                event.triggerEpochMillis,
                                replaceResult.newToken,
                                compCode
                            )
                            if (compOk) {
                                companionScheduledCount++
                            } else {
                                schedulingIncomplete = true
                            }
                        }
                    }
                }

                val exactAlarmsUsed = exactScheduledCount > 0
                val companionAlarmsUsed = companionScheduledCount > 0
                val successfullyScheduledEventsCount = if (canExact) {
                    minOf(exactScheduledCount, companionScheduledCount)
                } else {
                    companionScheduledCount
                }

                val hasFailures = oldCancelFailed || schedulingIncomplete || (attemptedEventsCount > 0 && (if (canExact) exactScheduledCount < attemptedEventsCount || companionScheduledCount < attemptedEventsCount else companionScheduledCount < attemptedEventsCount))

                if (hasFailures) {
                    return mapOf(
                        "success" to false,
                        "authorizationInvalidated" to true,
                        "token" to replaceResult.newToken,
                        "partialFailure" to true,
                        "errorCode" to if (oldCancelFailed) "OS_CLEANUP_INCOMPLETE" else "ALARM_SCHEDULING_INCOMPLETE",
                        "scheduledCount" to successfullyScheduledEventsCount,
                        "attemptedCount" to attemptedEventsCount,
                        "exactScheduledCount" to exactScheduledCount,
                        "companionScheduledCount" to companionScheduledCount,
                        "exactAlarmsUsed" to exactAlarmsUsed,
                        "companionAlarmsUsed" to companionAlarmsUsed,
                        "messageAr" to "تم تحديث الخطة، ولكن تعذر اكتمال جدولة بعض التنبيهات في النظام."
                    )
                }

                return mapOf(
                    "success" to true,
                    "authorizationInvalidated" to true,
                    "token" to replaceResult.newToken,
                    "scheduledCount" to successfullyScheduledEventsCount,
                    "attemptedCount" to attemptedEventsCount,
                    "exactScheduledCount" to exactScheduledCount,
                    "companionScheduledCount" to companionScheduledCount,
                    "exactAlarmsUsed" to exactAlarmsUsed,
                    "companionAlarmsUsed" to companionAlarmsUsed,
                    "messageAr" to if (attemptedEventsCount == 0) {
                        "تم تحديث جدول مواعيد الصلاة بنجاح (لا توجد مواعيد قادمة للجدولة)"
                    } else {
                        "تم تحديث جدول مواعيد الصلاة بنجاح"
                    }
                )
            }
        }
    }

    /**
     * Disables prayer alarms and stops any active adhan service.
     * The generation token is durably invalidated FIRST before OS cancellation.
     */
    fun disableAlarms(): Map<String, Any?> = coordinatorLock.withLock {
        val oldPlan = store.getActivePlan()

        // 1. DURABLY INVALIDATE FIRST
        val result = store.disable()
        when (result) {
            is DisableResult.PersistenceFailure -> {
                return mapOf(
                    "success" to false,
                    "errorCode" to "STORAGE_PERSISTENCE_FAILURE",
                    "messageAr" to result.messageAr
                )
            }
            is DisableResult.Success -> {
                // 2. Perform OS cleanup:
                var cleanupIncomplete = false
                if (oldPlan != null) {
                    for (ev in oldPlan.events) {
                        val alarmsCancelled = alarmScheduler.cancelAlarms(ev)
                        val notifCancelled = notificationGateway.cancelEventNotification(ev.eventKey)
                        if (!alarmsCancelled || !notifCancelled) {
                            cleanupIncomplete = true
                        }
                    }
                }

                val stopped = stopActiveAdhanPlayback()
                if (!stopped) {
                    cleanupIncomplete = true
                }

                if (cleanupIncomplete) {
                    return mapOf(
                        "success" to false,
                        "authorizationInvalidated" to true,
                        "token" to result.newToken,
                        "partialFailure" to true,
                        "errorCode" to "OS_CLEANUP_INCOMPLETE",
                        "messageAr" to "تم تعطيل المواعيد، ولكن تعذر إكمال بعض عمليات التنظيف في النظام."
                    )
                }

                return mapOf(
                    "success" to true,
                    "authorizationInvalidated" to true,
                    "token" to result.newToken,
                    "messageAr" to "تم تعطيل مواعيد الأذان وإلغاء التنبيهات بنجاح"
                )
            }
        }
    }

    /**
     * Resets all native state, invalidating token and clearing the consumed ledger.
     * The generation token is durably invalidated FIRST before OS cancellation.
     */
    fun resetAll(): Map<String, Any?> = coordinatorLock.withLock {
        val oldPlan = store.getActivePlan()

        // 1. DURABLY INVALIDATE & RESET FIRST
        val result = store.reset()
        when (result) {
            is ResetResult.PersistenceFailure -> {
                return mapOf(
                    "success" to false,
                    "errorCode" to "STORAGE_PERSISTENCE_FAILURE",
                    "messageAr" to result.messageAr
                )
            }
            is ResetResult.Success -> {
                // 2. Perform OS cleanup:
                var cleanupIncomplete = false
                if (oldPlan != null) {
                    for (ev in oldPlan.events) {
                        val alarmsCancelled = alarmScheduler.cancelAlarms(ev)
                        val notifCancelled = notificationGateway.cancelEventNotification(ev.eventKey)
                        if (!alarmsCancelled || !notifCancelled) {
                            cleanupIncomplete = true
                        }
                    }
                }

                val stopped = stopActiveAdhanPlayback()
                if (!stopped) {
                    cleanupIncomplete = true
                }

                if (cleanupIncomplete) {
                    return mapOf(
                        "success" to false,
                        "authorizationInvalidated" to true,
                        "token" to result.newToken,
                        "partialFailure" to true,
                        "errorCode" to "OS_CLEANUP_INCOMPLETE",
                        "messageAr" to "تمت إعادة ضبط المواعيد، ولكن تعذر إكمال بعض عمليات التنظيف في النظام."
                    )
                }

                return mapOf(
                    "success" to true,
                    "authorizationInvalidated" to true,
                    "token" to result.newToken,
                    "messageAr" to "تمت إعادة ضبط جدول مواعيد الأذان بالكامل"
                )
            }
        }
    }

    /**
     * Evaluates incoming alarm trigger and executes delivery safely.
     */
    fun handleAlarmTrigger(
        eventKey: String,
        token: Long,
        alarmType: AlarmTriggerType
    ) {
        coordinatorLock.withLock {
            val now = timeProvider.now()
            val canExact = alarmScheduler.canScheduleExactAlarms()
            val notifAllowed = notificationGateway.areNotificationsEnabled()
            val statusBlocked = notificationGateway.isPlaybackStatusChannelBlocked()
            val dndSuppressed = notificationGateway.isDndOrSilentActive()
            val isServiceRunning = serviceGateway.isServiceRunning()

            // 1. Manual playback lease check BEFORE state machine chooses audible branch:
            if (isManualPlaybackLeaseActive()) {
                val plan = store.getActivePlan()
                val event = plan?.events?.firstOrNull { it.eventKey == eventKey }
                if (store.isEnabled() && store.getGenerationToken() == token && event != null) {
                    val suppressed = stateMachine.markManualSuppressed(
                        expectedToken = token,
                        eventKey = eventKey,
                        nowEpochMillis = now,
                        alarmType = alarmType
                    )
                    if (suppressed) {
                        notificationGateway.postSilentManualSuppressedAlert(
                            eventKey = eventKey,
                            prayerKey = event.prayerKey,
                            cityNameAr = plan.cityNameAr
                        )
                    }
                }
                return@withLock
            }

            val outcome = stateMachine.processAlarmTrigger(
                intentToken = token,
                eventKey = eventKey,
                alarmType = alarmType,
                nowEpochMillis = now,
                canScheduleExactAlarms = canExact,
                notificationsAllowed = notifAllowed,
                statusChannelBlocked = statusBlocked,
                dndOrSilentSuppresses = dndSuppressed,
                isServiceCurrentlyActive = isServiceRunning
            )

            when (outcome) {
                is AlarmProcessingOutcome.StartFullAdhan -> {
                    val started = serviceGateway.startAdhanPlaybackService(eventKey, token)
                    if (!started) {
                        handleServicePrestartFailure(
                            token = token,
                            eventKey = eventKey,
                            reason = "service_launch_failed",
                            nowEpochMillis = now
                        )
                    }
                }
                is AlarmProcessingOutcome.DeliverShortFallback -> {
                    if (!isManualPlaybackLeaseActive()) {
                        if (!notificationGateway.isVoiceChannelBlocked(outcome.event.voiceId)) {
                            val posted = notificationGateway.postShortAlert(
                                eventKey = eventKey,
                                prayerKey = outcome.event.prayerKey,
                                cityNameAr = outcome.plan.cityNameAr,
                                voiceId = outcome.event.voiceId
                            )
                            if (posted) {
                                postedOwnedNotificationKeys.add(eventKey)
                            }
                        }
                    } else {
                        val suppressed = stateMachine.markManualSuppressed(
                            expectedToken = token,
                            eventKey = eventKey,
                            nowEpochMillis = now,
                            alarmType = alarmType
                        )
                        if (suppressed) {
                            notificationGateway.postSilentManualSuppressedAlert(
                                eventKey = eventKey,
                                prayerKey = outcome.event.prayerKey,
                                cityNameAr = outcome.plan.cityNameAr
                            )
                        }
                    }
                }
                is AlarmProcessingOutcome.PersistenceFailure -> {
                    // Fail closed: zero audible side effects!
                }
                is AlarmProcessingOutcome.TriggerTooEarly -> {
                    // Drop early triggers safely; do not play future prayer early
                }
                else -> {
                    // Safely dropped (stale, duplicate, expired, or already delivered)
                }
            }
        }
    }

    /**
     * Restores FUTURE saved alarms upon reboot, package update, or time changes.
     * NEVER plays sound or launches service from boot/restore!
     */
    fun restoreScheduleOnBootOrTimeChange() {
        coordinatorLock.withLock {
            if (!store.isEnabled()) return@withLock
            val plan = store.getActivePlan() ?: return@withLock

            val now = timeProvider.now()
            val token = store.getGenerationToken()
            val ledger = store.getConsumedLedgerSnapshot()
            val canExact = alarmScheduler.canScheduleExactAlarms()

            for (event in plan.events) {
                val record = ledger[event.eventKey]
                // Skip already delivered events
                if (record != null && record.state.isTerminal) {
                    continue
                }

                // Restore FUTURE events only
                if (event.triggerEpochMillis > now) {
                    val exactCode = event.getPendingIntentRequestCode(AlarmTriggerType.EXACT)
                    val compCode = event.getPendingIntentRequestCode(AlarmTriggerType.COMPANION)

                    if (canExact) {
                        alarmScheduler.scheduleExact(event.eventKey, event.triggerEpochMillis, token, exactCode)
                        alarmScheduler.scheduleCompanion(
                            event.eventKey,
                            event.triggerEpochMillis + COMPANION_OFFSET_WHEN_EXACT_ALLOWED_MILLIS,
                            token,
                            compCode
                        )
                    } else {
                        alarmScheduler.scheduleCompanion(event.eventKey, event.triggerEpochMillis, token, compCode)
                    }
                }
            }
        }
    }

    /**
     * Structured result for authorizeAndStartPlayback transitions.
     */
    sealed class PlaybackStartResult {
        data object Success : PlaybackStartResult()
        data class NotAuthorized(val reason: String) : PlaybackStartResult()
        data class Suppressed(val reason: String) : PlaybackStartResult()
        data class PlayClaimPersistenceFailed(val eventKey: String) : PlaybackStartResult()
        data class PhysicalStartFailed(val error: Throwable?) : PlaybackStartResult()
        data class ConsumedRecordPersistenceFailed(val eventKey: String) : PlaybackStartResult()

        val isStarted: Boolean
            get() = this is Success || this is ConsumedRecordPersistenceFailed

        val isFullyDurable: Boolean
            get() = this is Success
    }

    /**
     * Unified locked handler for all service pre-start failure branches.
     * Holds the exact same coordinatorLock as acquireManualPlaybackLease,
     * authorizeAndStartPlayback, and handleAlarmTrigger across:
     * 1. Enabled / token / event in plan validation
     * 2. Atomic manual playback lease check under lock
     * 3. Durable state machine transition (MANUAL_SUPPRESSED if leased, SHORT_DELIVERED if not)
     * 4. Notification emission (silent notice if leased, audible short alert if not leased and voice channel not blocked)
     *
     * Invariants:
     * - When leased: eligible prestart claim transitions to MANUAL_SUPPRESSED and emits ONE dedicated silent notice; zero audible sound.
     * - When ledger update fails: returns false with zero notification effects.
     * - When PLAY_CLAIMED / FULL_CONSUMED / SHORT_DELIVERED / terminal: never rewrites to fallback; returns false with zero notification effects.
     * - Known EXACT pre-start failure when not leased within lateness window: transitions to SHORT_DELIVERED and emits ONE short fallback alert.
     */
    fun handleServicePrestartFailure(
        token: Long,
        eventKey: String,
        reason: String,
        nowEpochMillis: Long = timeProvider.now()
    ): Boolean = coordinatorLock.withLock {
        // 1. Re-validate enabled state and exact generation token under lock
        if (!store.isEnabled() || store.getGenerationToken() != token) {
            return@withLock false
        }

        // 2. Re-validate active plan and event presence
        val plan = store.getActivePlan() ?: return@withLock false
        val event = plan.events.firstOrNull { it.eventKey == eventKey } ?: return@withLock false

        // 3. Atomically evaluate manual playback lease under coordinatorLock
        if (isManualPlaybackLeaseActive()) {
            val suppressed = stateMachine.markManualSuppressed(
                expectedToken = token,
                eventKey = eventKey,
                nowEpochMillis = nowEpochMillis,
                alarmType = AlarmTriggerType.EXACT
            )
            if (suppressed) {
                notificationGateway.postSilentManualSuppressedAlert(
                    eventKey = eventKey,
                    prayerKey = event.prayerKey,
                    cityNameAr = plan.cityNameAr
                )
            }
            return@withLock suppressed
        } else {
            val fallbackAllowed = stateMachine.handleServiceStartupFailure(
                expectedToken = token,
                eventKey = eventKey,
                reason = reason,
                nowEpochMillis = nowEpochMillis
            )
            if (fallbackAllowed) {
                if (!notificationGateway.isVoiceChannelBlocked(event.voiceId)) {
                    val posted = notificationGateway.postShortAlert(
                        eventKey = eventKey,
                        prayerKey = event.prayerKey,
                        cityNameAr = plan.cityNameAr,
                        voiceId = event.voiceId
                    )
                    if (posted) {
                        postedOwnedNotificationKeys.add(eventKey)
                    }
                }
                return@withLock true
            }
            return@withLock false
        }
    }

    /**
     * Executes final authorization recheck and physical MediaPlayer start under
     * the coordinator's synchronization lock.
     * Prevents race conditions where disable/reset invalidates the store while
     * MediaPlayer is preparing, ensuring zero stale sound after reset.
     */
    fun authorizeAndStartPlayback(
        token: Long,
        eventKey: String,
        nowEpochMillis: Long,
        isSuppressed: () -> Boolean,
        onPhysicalStart: () -> Boolean
    ): PlaybackStartResult = coordinatorLock.withLock {
        // 1. Re-validate enabled state and exact generation token under lock
        if (!store.isEnabled() || store.getGenerationToken() != token) {
            return PlaybackStartResult.NotAuthorized("token_mismatch_or_disabled")
        }

        // 2. Re-validate that event is still present in current active plan
        val plan = store.getActivePlan()
            ?: return PlaybackStartResult.NotAuthorized("no_active_plan")
        if (plan.events.none { it.eventKey == eventKey }) {
            return PlaybackStartResult.NotAuthorized("event_not_in_plan")
        }

        // 3a. Re-validate manual playback lease immediately before start under shared lock:
        if (isManualPlaybackLeaseActive()) {
            val suppressed = stateMachine.markManualSuppressed(
                expectedToken = token,
                eventKey = eventKey,
                nowEpochMillis = nowEpochMillis,
                alarmType = AlarmTriggerType.EXACT
            )
            if (suppressed) {
                val event = plan.events.first { it.eventKey == eventKey }
                notificationGateway.postSilentManualSuppressedAlert(
                    eventKey = eventKey,
                    prayerKey = event.prayerKey,
                    cityNameAr = plan.cityNameAr
                )
            }
            return PlaybackStartResult.Suppressed("manual_playback_lease_active")
        }

        // 3b. Re-validate silent/DND or status channel suppression
        if (isSuppressed()) {
            stateMachine.handleServiceStartupFailure(
                expectedToken = token,
                eventKey = eventKey,
                reason = "suppressed_immediately_before_play",
                nowEpochMillis = nowEpochMillis
            )
            return PlaybackStartResult.Suppressed("suppressed_by_user_or_system")
        }

        // 4. Mark durable PLAY_CLAIMED before start
        val claimed = stateMachine.markPlayClaimedBeforeStart(
            expectedToken = token,
            eventKey = eventKey,
            nowEpochMillis = nowEpochMillis
        )
        if (!claimed) {
            return PlaybackStartResult.PlayClaimPersistenceFailed(eventKey)
        }

        // 5. Execute physical MediaPlayer.start()
        val physicallyStarted = try {
            onPhysicalStart()
        } catch (e: Exception) {
            false
        }

        if (!physicallyStarted) {
            return PlaybackStartResult.PhysicalStartFailed(null)
        }

        // 6. Mark full playback started permanently in durable ledger
        val fullConsumedPersisted = stateMachine.markFullPlaybackStarted(
            expectedToken = token,
            eventKey = eventKey,
            nowEpochMillis = nowEpochMillis
        )

        if (!fullConsumedPersisted) {
            // Finding 3: Consumed record failed to persist. Audio HAS physically started,
            // so we must NEVER mark fallback eligible (state remains PLAY_CLAIMED in store,
            // which guarantees NO companion fallback and NO full replay: at-most-once).
            // Stop confirmed and return structured failure; do NOT return success or claim fully durable.
            serviceGateway.stopAdhanPlaybackService()
            return PlaybackStartResult.ConsumedRecordPersistenceFailed(eventKey)
        }

        return PlaybackStartResult.Success
    }

    /**
     * Confirms immediate synchronous stop of active adhan playback and release of resources.
     * Required for manual foreground Quran audio handoff.
     * Serialized under coordinatorLock to prevent race with physical start.
     */
    fun stopActiveAdhanPlayback(): Boolean = coordinatorLock.withLock {
        val serviceStopped = serviceGateway.stopAdhanPlaybackService()
        val notifsCancelled = cancelOwnedEventNotificationsUnderLock()
        return serviceStopped && notifsCancelled
    }

    fun getState(): Map<String, Any?> = coordinatorLock.withLock {
        val plan = store.getActivePlan()
        val now = timeProvider.now()
        val futureCount = plan?.events?.count { it.triggerEpochMillis > now } ?: 0

        return mapOf(
            "enabled" to store.isEnabled(),
            "generationToken" to store.getGenerationToken(),
            "canScheduleExactAlarms" to alarmScheduler.canScheduleExactAlarms(),
            "notificationsAllowed" to notificationGateway.areNotificationsEnabled(),
            "isPlaybackStatusChannelBlocked" to notificationGateway.isPlaybackStatusChannelBlocked(),
            "isDndOrSilentActive" to notificationGateway.isDndOrSilentActive(),
            "isServiceRunning" to serviceGateway.isServiceRunning(),
            "isManualPlaybackLeaseActive" to isManualPlaybackLeaseActive(),
            "futureEventsCount" to futureCount,
            "cityId" to (plan?.cityId ?: 0),
            "cityNameAr" to (plan?.cityNameAr ?: ""),
            "timezone" to (plan?.timezone ?: ""),
            "coverageHorizonUtc" to (plan?.coverageHorizonUtc ?: 0L),
            "consumedLedgerCount" to store.getConsumedLedgerSnapshot().size
        )
    }
}
