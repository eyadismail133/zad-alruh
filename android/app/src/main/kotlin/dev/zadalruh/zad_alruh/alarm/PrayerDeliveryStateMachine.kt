package dev.zadalruh.zad_alruh.alarm

import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Outcomes returned when an alarm trigger is evaluated.
 */
sealed class AlarmProcessingOutcome {
    object StaleOrDisabled : AlarmProcessingOutcome()
    object StaleGenerationToken : AlarmProcessingOutcome()
    object EventNotInActivePlan : AlarmProcessingOutcome()
    object AlreadyDelivered : AlarmProcessingOutcome()
    object ExpiredLate : AlarmProcessingOutcome()
    object TriggerTooEarly : AlarmProcessingOutcome()
    object ActiveClaimInProgress : AlarmProcessingOutcome()
    data class PersistenceFailure(val eventKey: String, val attemptedState: DeliveryState) : AlarmProcessingOutcome()
    data class StartFullAdhan(
        val event: PrayerEventRecord,
        val plan: PrayerPlan,
        val token: Long
    ) : AlarmProcessingOutcome()
    data class DeliverShortFallback(
        val event: PrayerEventRecord,
        val plan: PrayerPlan,
        val reason: String
    ) : AlarmProcessingOutcome()
}

/**
 * Atomic durable event delivery state machine.
 * Enforces single delivery, exact claim before FGS, companion viable fallback,
 * durable playclaim before MediaPlayer.start, and zero double sound.
 * Fails closed on any persistence failure.
 */
class PrayerDeliveryStateMachine(private val store: PrayerAlarmStore) {
    private val lock = ReentrantLock()

    companion object {
        const val LATENESS_WINDOW_MILLIS = 5L * 60L * 1000L // 5 minutes
        const val EARLY_TRIGGER_TOLERANCE_MILLIS = 5L * 1000L // 5 seconds
        const val ABANDONED_CLAIM_THRESHOLD_MILLIS = 30L * 1000L // 30 seconds
    }

    /**
     * Processes an incoming alarm trigger (exact or companion) under atomic lock.
     */
    fun processAlarmTrigger(
        intentToken: Long,
        eventKey: String,
        alarmType: AlarmTriggerType,
        nowEpochMillis: Long,
        canScheduleExactAlarms: Boolean,
        notificationsAllowed: Boolean,
        statusChannelBlocked: Boolean,
        dndOrSilentSuppresses: Boolean,
        isServiceCurrentlyActive: Boolean
    ): AlarmProcessingOutcome = lock.withLock {
        if (!store.isEnabled()) {
            return AlarmProcessingOutcome.StaleOrDisabled
        }

        if (intentToken != store.getGenerationToken()) {
            return AlarmProcessingOutcome.StaleGenerationToken
        }

        val plan = store.getActivePlan() ?: return AlarmProcessingOutcome.StaleOrDisabled
        val event = plan.events.firstOrNull { it.eventKey == eventKey }
            ?: return AlarmProcessingOutcome.EventNotInActivePlan

        // Early trigger guard: do not allow early broadcasts to deliver future prayer prematurely
        if (nowEpochMillis < event.triggerEpochMillis - EARLY_TRIGGER_TOLERANCE_MILLIS) {
            return AlarmProcessingOutcome.TriggerTooEarly
        }

        // Lateness check: if alarm fires > 5 minutes after scheduled trigger time, drop as expired
        if (nowEpochMillis > event.triggerEpochMillis + LATENESS_WINDOW_MILLIS) {
            val ok = store.updateConsumedRecord(
                ConsumedRecord(
                    eventKey = eventKey,
                    state = DeliveryState.EXPIRED_LATE,
                    timestampMillis = nowEpochMillis,
                    deliveryType = alarmType.key,
                    details = "Alarm triggered after 5-minute lateness window"
                )
            )
            if (!ok) {
                return AlarmProcessingOutcome.PersistenceFailure(eventKey, DeliveryState.EXPIRED_LATE)
            }
            return AlarmProcessingOutcome.ExpiredLate
        }

        val currentRecord = store.getConsumedRecord(eventKey)
        if (currentRecord != null) {
            if (currentRecord.state.isTerminal) {
                // Permanently consumed: drops immediately, preventing double sound
                return AlarmProcessingOutcome.AlreadyDelivered
            }

            if (currentRecord.state == DeliveryState.PLAY_CLAIMED) {
                // Once durable PLAY_CLAIMED is reached, physical full playback MAY have started.
                // Strictly one-way: NO short fallback and NO full replay from this state!
                // Prevents double sound if physical audio started then crashed or FULL_CONSUMED write failed.
                if (isServiceCurrentlyActive) {
                    return AlarmProcessingOutcome.ActiveClaimInProgress
                }
                return AlarmProcessingOutcome.AlreadyDelivered
            }

            if (currentRecord.state == DeliveryState.EXACT_CLAIMED) {
                if (alarmType == AlarmTriggerType.EXACT) {
                    // Duplicate exact alarm fire
                    return AlarmProcessingOutcome.ActiveClaimInProgress
                }

                // Companion fire while in EXACT_CLAIMED
                val age = nowEpochMillis - currentRecord.timestampMillis
                val isAbandoned = !isServiceCurrentlyActive && (age > ABANDONED_CLAIM_THRESHOLD_MILLIS)
                val isWithinLateness = nowEpochMillis <= event.triggerEpochMillis + LATENESS_WINDOW_MILLIS

                if (isAbandoned && isWithinLateness) {
                    // Process died before FGS could start; companion delivers short fallback once
                    val persisted = store.updateConsumedRecord(
                        ConsumedRecord(
                            eventKey = eventKey,
                            state = DeliveryState.SHORT_DELIVERED,
                            timestampMillis = nowEpochMillis,
                            deliveryType = alarmType.key,
                            details = "One-time short fallback after abandoned EXACT_CLAIMED"
                        )
                    )
                    if (!persisted) {
                        return AlarmProcessingOutcome.PersistenceFailure(eventKey, DeliveryState.SHORT_DELIVERED)
                    }
                    return AlarmProcessingOutcome.DeliverShortFallback(
                        event = event,
                        plan = plan,
                        reason = "abandoned_exact_claim_crash"
                    )
                }

                // Exact service is actively starting or running; companion yields
                return AlarmProcessingOutcome.ActiveClaimInProgress
            }
        }

        // Event is PENDING / unclaimed
        if (alarmType == AlarmTriggerType.EXACT) {
            val fullAllowed = canScheduleExactAlarms &&
                notificationsAllowed &&
                !statusChannelBlocked &&
                !dndOrSilentSuppresses &&
                (event.mode == PrayerAlarmMode.FULL_ADHAN.key)

            if (fullAllowed) {
                // Reserve/claim exact delivery before FGS launch
                val persisted = store.updateConsumedRecord(
                    ConsumedRecord(
                        eventKey = eventKey,
                        state = DeliveryState.EXACT_CLAIMED,
                        timestampMillis = nowEpochMillis,
                        deliveryType = alarmType.key,
                        details = "Exact claim reserved before FGS launch"
                    )
                )
                if (!persisted) {
                    // Fail closed on persistence failure: zero side effects!
                    return AlarmProcessingOutcome.PersistenceFailure(eventKey, DeliveryState.EXACT_CLAIMED)
                }
                return AlarmProcessingOutcome.StartFullAdhan(
                    event = event,
                    plan = plan,
                    token = intentToken
                )
            } else {
                // Approximate / fallback notification path (permission denied, DND/silent, or short_alert)
                val persisted = store.updateConsumedRecord(
                    ConsumedRecord(
                        eventKey = eventKey,
                        state = DeliveryState.SHORT_DELIVERED,
                        timestampMillis = nowEpochMillis,
                        deliveryType = alarmType.key,
                        details = "Short notification fallback (exact denied or suppressed)"
                    )
                )
                if (!persisted) {
                    return AlarmProcessingOutcome.PersistenceFailure(eventKey, DeliveryState.SHORT_DELIVERED)
                }
                return AlarmProcessingOutcome.DeliverShortFallback(
                    event = event,
                    plan = plan,
                    reason = "exact_denied_or_suppressed"
                )
            }
        } else {
            // Companion alarm trigger: NEVER launches FGS!
            val persisted = store.updateConsumedRecord(
                ConsumedRecord(
                    eventKey = eventKey,
                    state = DeliveryState.SHORT_DELIVERED,
                    timestampMillis = nowEpochMillis,
                    deliveryType = alarmType.key,
                    details = "Companion inexact short alert delivery"
                )
            )
            if (!persisted) {
                return AlarmProcessingOutcome.PersistenceFailure(eventKey, DeliveryState.SHORT_DELIVERED)
            }
            return AlarmProcessingOutcome.DeliverShortFallback(
                event = event,
                plan = plan,
                reason = "companion_fallback_delivery"
            )
        }
    }

    /**
     * Called by AdhanMediaPlaybackService immediately before MediaPlayer.start().
     * Atomically validates that the store is still enabled with the exact same generation token
     * and event in EXACT_CLAIMED state, then persists PLAY_CLAIMED durably to prevent crash-gap replay.
     * Fails closed if token changed, plan disabled, or persistence failed.
     */
    fun markPlayClaimedBeforeStart(
        expectedToken: Long,
        eventKey: String,
        nowEpochMillis: Long
    ): Boolean = lock.withLock {
        if (!store.isEnabled()) return false
        if (store.getGenerationToken() != expectedToken) return false

        val plan = store.getActivePlan() ?: return false
        if (plan.events.none { it.eventKey == eventKey }) return false

        val currentRecord = store.getConsumedRecord(eventKey)
        // Must be currently in EXACT_CLAIMED state
        if (currentRecord?.state != DeliveryState.EXACT_CLAIMED) return false

        return store.updateConsumedRecord(
            ConsumedRecord(
                eventKey = eventKey,
                state = DeliveryState.PLAY_CLAIMED,
                timestampMillis = nowEpochMillis,
                deliveryType = AlarmTriggerType.EXACT.key,
                details = "Durable play claim before MediaPlayer.start"
            )
        )
    }

    /**
     * Called by AdhanMediaPlaybackService when playback successfully begins.
     * Atomically validates token and current state (PLAY_CLAIMED) and transitions to FULL_CONSUMED.
     */
    fun markFullPlaybackStarted(
        expectedToken: Long,
        eventKey: String,
        nowEpochMillis: Long
    ): Boolean = lock.withLock {
        if (!store.isEnabled()) return false
        if (store.getGenerationToken() != expectedToken) return false

        val plan = store.getActivePlan() ?: return false
        if (plan.events.none { it.eventKey == eventKey }) return false

        val currentRecord = store.getConsumedRecord(eventKey)
        if (currentRecord?.state != DeliveryState.PLAY_CLAIMED) return false

        return store.updateConsumedRecord(
            ConsumedRecord(
                eventKey = eventKey,
                state = DeliveryState.FULL_CONSUMED,
                timestampMillis = nowEpochMillis,
                deliveryType = AlarmTriggerType.EXACT.key,
                details = "Full adhan playback started and permanently consumed"
            )
        )
    }

    /**
     * Called if FGS fails to start, audio focus is denied, or channel is blocked.
     * Never rewrites FULL_CONSUMED or SHORT_DELIVERED, and never emits duplicate fallback.
     * Fails closed on persistence failure.
     */
    fun handleServiceStartupFailure(
        expectedToken: Long,
        eventKey: String,
        reason: String,
        nowEpochMillis: Long
    ): Boolean = lock.withLock {
        if (!store.isEnabled()) return false
        if (store.getGenerationToken() != expectedToken) return false

        val plan = store.getActivePlan() ?: return false
        val event = plan.events.firstOrNull { it.eventKey == eventKey } ?: return false

        val currentRecord = store.getConsumedRecord(eventKey) ?: return false

        // Never rewrite terminal states or emit duplicate fallback!
        if (currentRecord.state.isTerminal) {
            return false
        }

        // Failure known BEFORE possible start can transition to fallback only if proven no sound (EXACT_CLAIMED).
        // Once PLAY_CLAIMED is reached, physical sound may already have started; state changes cannot
        // retroactively turn ambiguous claimed full into fallback.
        if (currentRecord.state != DeliveryState.EXACT_CLAIMED) {
            return false
        }

        val isWithinLateness = nowEpochMillis <= event.triggerEpochMillis + LATENESS_WINDOW_MILLIS
        if (isWithinLateness) {
            val ok = store.updateConsumedRecord(
                ConsumedRecord(
                    eventKey = eventKey,
                    state = DeliveryState.SHORT_DELIVERED,
                    timestampMillis = nowEpochMillis,
                    deliveryType = AlarmTriggerType.EXACT.key,
                    details = "Short fallback delivered after service failure: $reason"
                )
            )
            return ok
        } else {
            val ok = store.updateConsumedRecord(
                ConsumedRecord(
                    eventKey = eventKey,
                    state = DeliveryState.SUPPRESSED_OR_FAILED,
                    timestampMillis = nowEpochMillis,
                    deliveryType = AlarmTriggerType.EXACT.key,
                    details = "Service failed outside lateness window: $reason"
                )
            )
            return false
        }
    }

    /**
     * Called when a manual playback lease is active.
     * Transitions an eligible due event (PENDING or EXACT_CLAIMED) to terminal MANUAL_SUPPRESSED.
     * Protects PENDING and known pre-start EXACT_CLAIMED.
     * Never rewrites PLAY_CLAIMED, terminal states, or early/expired cases.
     * Fails closed on persistence failure.
     */
    fun markManualSuppressed(
        expectedToken: Long,
        eventKey: String,
        nowEpochMillis: Long,
        alarmType: AlarmTriggerType
    ): Boolean = lock.withLock {
        if (!store.isEnabled()) return false
        if (store.getGenerationToken() != expectedToken) return false

        val plan = store.getActivePlan() ?: return false
        val event = plan.events.firstOrNull { it.eventKey == eventKey } ?: return false

        // Early trigger guard
        if (nowEpochMillis < event.triggerEpochMillis - EARLY_TRIGGER_TOLERANCE_MILLIS) {
            return false
        }
        // Lateness check
        if (nowEpochMillis > event.triggerEpochMillis + LATENESS_WINDOW_MILLIS) {
            return false
        }

        val currentRecord = store.getConsumedRecord(eventKey)
        if (currentRecord != null) {
            // Never rewrite terminal states
            if (currentRecord.state.isTerminal) return false
            // Never rewrite PLAY_CLAIMED
            if (currentRecord.state == DeliveryState.PLAY_CLAIMED) return false
            // Only EXACT_CLAIMED is valid to transition here if record exists
            if (currentRecord.state != DeliveryState.EXACT_CLAIMED) return false
        }

        return store.updateConsumedRecord(
            ConsumedRecord(
                eventKey = eventKey,
                state = DeliveryState.MANUAL_SUPPRESSED,
                timestampMillis = nowEpochMillis,
                deliveryType = alarmType.key,
                details = "Manual playback lease active; silent prayer alert posted"
            )
        )
    }
}
