package dev.zadalruh.zad_alruh

import dev.zadalruh.zad_alruh.alarm.AlarmProcessingOutcome
import dev.zadalruh.zad_alruh.alarm.AlarmSchedulerGateway
import dev.zadalruh.zad_alruh.alarm.AlarmTriggerType
import dev.zadalruh.zad_alruh.alarm.DeliveryState
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmCoordinator
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmCoordinator.PlaybackStartResult
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmStore
import dev.zadalruh.zad_alruh.alarm.PrayerDeliveryStateMachine
import dev.zadalruh.zad_alruh.alarm.PrayerEventRecord
import dev.zadalruh.zad_alruh.alarm.PrayerPlan
import dev.zadalruh.zad_alruh.alarm.ReplacePlanResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class PrayerAlarmCoordinatorTest {

    private lateinit var storage: InMemoryStorageDriver
    private lateinit var store: PrayerAlarmStore
    private lateinit var stateMachine: PrayerDeliveryStateMachine
    private lateinit var timeProvider: MutableTimeProvider
    private lateinit var scheduler: FakeAlarmScheduler
    private lateinit var notifGateway: FakeNotificationGateway
    private lateinit var serviceGateway: FakeServiceGateway
    private lateinit var coordinator: PrayerAlarmCoordinator

    private val baseTime = 1760000000000L
    private val fajrKey = "360630:2026-10-07:fajr"
    private val fajrTrigger = baseTime + 60000L

    private fun samplePlan(token: Long): PrayerPlan {
        return PrayerPlan(
            expectedToken = token,
            cityId = 360630,
            cityNameAr = "القاهرة",
            timezone = "Africa/Cairo",
            generalVoiceId = "adam",
            fajrVoiceId = "malmo_fajr",
            mode = "full_adhan",
            coverageHorizonUtc = baseTime + 864000000L,
            events = listOf(
                PrayerEventRecord(
                    eventKey = fajrKey,
                    prayerKey = "fajr",
                    calculationCivilDate = "2026-10-07",
                    triggerEpochMillis = fajrTrigger,
                    voiceId = "malmo_fajr",
                    mode = "full_adhan"
                )
            )
        )
    }

    private fun sampleRawPlan(token: Long): Map<String, Any> {
        return mapOf(
            "expectedToken" to token,
            "cityId" to 360630,
            "cityNameAr" to "القاهرة",
            "timezone" to "Africa/Cairo",
            "generalVoiceId" to "adam",
            "fajrVoiceId" to "malmo_fajr",
            "mode" to "full_adhan",
            "coverageHorizonUtc" to baseTime + 864000000L,
            "events" to listOf(
                mapOf(
                    "eventKey" to fajrKey,
                    "prayerKey" to "fajr",
                    "calculationCivilDate" to "2026-10-07",
                    "triggerEpochMillis" to fajrTrigger,
                    "voiceId" to "malmo_fajr",
                    "mode" to "full_adhan"
                )
            )
        )
    }

    private fun sampleRawPlanWithEvents(token: Long, events: List<Map<String, Any>>): Map<String, Any> {
        return mapOf(
            "expectedToken" to token,
            "cityId" to 360630,
            "cityNameAr" to "القاهرة",
            "timezone" to "Africa/Cairo",
            "generalVoiceId" to "adam",
            "fajrVoiceId" to "malmo_fajr",
            "mode" to "full_adhan",
            "coverageHorizonUtc" to baseTime + 864000000L,
            "events" to events
        )
    }

    @Before
    fun setUp() {
        storage = InMemoryStorageDriver()
        store = PrayerAlarmStore(storage)
        stateMachine = PrayerDeliveryStateMachine(store)
        timeProvider = MutableTimeProvider(baseTime)
        scheduler = FakeAlarmScheduler()
        notifGateway = FakeNotificationGateway()
        serviceGateway = FakeServiceGateway()

        coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        // Initial setup: install active plan at token 1 -> increments to token 2
        store.replacePlan(1L, samplePlan(1L), baseTime)
    }

    @Test
    fun testAuthorizeAndStartPlaybackUnderLockBlocksStaleSoundAfterResetOrDisable() {
        val currentToken = store.getGenerationToken()

        // 1. Claim exact trigger
        val outcome = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )
        assertTrue(outcome is AlarmProcessingOutcome.StartFullAdhan)

        var physicalStarts = 0
        val authorized = coordinator.authorizeAndStartPlayback(
            token = currentToken,
            eventKey = fajrKey,
            nowEpochMillis = fajrTrigger + 100L,
            isSuppressed = { false },
            onPhysicalStart = {
                physicalStarts++
                true
            }
        )

        assertTrue(authorized is PlaybackStartResult.Success)
        assertTrue(authorized.isFullyDurable)
        assertEquals(1, physicalStarts)
        assertEquals(DeliveryState.FULL_CONSUMED, store.getConsumedRecord(fajrKey)?.state)

        // 2. Disable store -> attempt start with old token or after disable MUST be rejected without sound
        coordinator.disableAlarms()

        var staleStarts = 0
        val rejectedAfterDisable = coordinator.authorizeAndStartPlayback(
            token = currentToken,
            eventKey = fajrKey,
            nowEpochMillis = fajrTrigger + 200L,
            isSuppressed = { false },
            onPhysicalStart = {
                staleStarts++
                true
            }
        )

        assertTrue(rejectedAfterDisable is PlaybackStartResult.NotAuthorized)
        assertFalse(rejectedAfterDisable.isFullyDurable)
        assertEquals(0, staleStarts)
    }

    @Test
    fun testOldGenerationLateTriggerCannotStartPhysicalAudio() {
        // Current token is 2L, late broadcast arrives with old token 1L
        var physicalStarts = 0
        val result = coordinator.authorizeAndStartPlayback(
            token = 1L,
            eventKey = fajrKey,
            nowEpochMillis = fajrTrigger,
            isSuppressed = { false },
            onPhysicalStart = {
                physicalStarts++
                true
            }
        )

        assertTrue(result is PlaybackStartResult.NotAuthorized)
        assertFalse(result.isFullyDurable)
        assertEquals(0, physicalStarts)
    }

    @Test
    fun testFailedConsumedWritePostStartStopsServiceAndMaintainsNoFallback() {
        val currentToken = store.getGenerationToken()

        // 1. Exact alarm claims delivery
        stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )
        assertEquals(DeliveryState.EXACT_CLAIMED, store.getConsumedRecord(fajrKey)?.state)

        serviceGateway.running = true
        var physicalStarts = 0

        // In onPhysicalStart, physical start happens, but we simulate storage failure for the post-start write:
        val result = coordinator.authorizeAndStartPlayback(
            token = currentToken,
            eventKey = fajrKey,
            nowEpochMillis = fajrTrigger + 100L,
            isSuppressed = { false },
            onPhysicalStart = {
                physicalStarts++
                // Fail storage write specifically for markFullPlaybackStarted:
                storage.failWrites = true
                true
            }
        )

        // Invariant: Structured failure returned; does NOT claim fully durable post-start!
        assertTrue(result is PlaybackStartResult.ConsumedRecordPersistenceFailed)
        assertFalse(result.isFullyDurable)
        assertEquals(1, physicalStarts)

        // Invariant: Service stop was confirmed!
        assertFalse(serviceGateway.running)

        // Invariant: Ledger state remains PLAY_CLAIMED
        assertEquals(DeliveryState.PLAY_CLAIMED, store.getConsumedRecord(fajrKey)?.state)

        // Invariant: Subsequent companion alarm drops without fallback and without full replay (at-most-once preserved!)
        storage.failWrites = false
        val companionOutcome = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.COMPANION,
            nowEpochMillis = fajrTrigger + 45000L,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )
        assertEquals(AlarmProcessingOutcome.AlreadyDelivered, companionOutcome)
    }

    @Test
    fun testSerializedAuthorizedStartThenConfirmedStop() {
        val currentToken = store.getGenerationToken()

        stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )

        val result = coordinator.authorizeAndStartPlayback(
            token = currentToken,
            eventKey = fajrKey,
            nowEpochMillis = fajrTrigger + 100L,
            isSuppressed = { false },
            onPhysicalStart = {
                serviceGateway.running = true
                true
            }
        )

        assertTrue(result is PlaybackStartResult.Success)
        assertTrue(serviceGateway.running)

        val stopped = coordinator.stopActiveAdhanPlayback()
        assertTrue(stopped)
        assertFalse(serviceGateway.running)
    }

    @Test
    fun testReplacePlanFailedExactSchedulingSurfacesFailureAndTruthfulCounters() {
        val currentToken = store.getGenerationToken()
        scheduler.failExact = true

        val res = coordinator.replacePlan(sampleRawPlan(currentToken))

        assertEquals(false, res["success"])
        assertEquals(true, res["authorizationInvalidated"])
        assertEquals(true, res["partialFailure"])
        assertEquals("ALARM_SCHEDULING_INCOMPLETE", res["errorCode"])
        assertEquals(false, res["exactAlarmsUsed"])
        assertEquals(true, res["companionAlarmsUsed"])
        assertEquals(0, res["exactScheduledCount"])
        assertEquals(1, res["companionScheduledCount"])
        assertEquals(1, res["attemptedCount"])
    }

    @Test
    fun testReplacePlanFailedCompanionSchedulingSurfacesFailureAndTruthfulCounters() {
        val currentToken = store.getGenerationToken()
        scheduler.failCompanion = true

        val res = coordinator.replacePlan(sampleRawPlan(currentToken))

        assertEquals(false, res["success"])
        assertEquals(true, res["authorizationInvalidated"])
        assertEquals(true, res["partialFailure"])
        assertEquals("ALARM_SCHEDULING_INCOMPLETE", res["errorCode"])
        assertEquals(true, res["exactAlarmsUsed"])
        assertEquals(false, res["companionAlarmsUsed"])
        assertEquals(1, res["exactScheduledCount"])
        assertEquals(0, res["companionScheduledCount"])
    }

    @Test
    fun testReplacePlanFailedOldAlarmCancelSurfacesCleanupIncomplete() {
        val currentToken = store.getGenerationToken()
        scheduler.failCancel = true

        val res = coordinator.replacePlan(sampleRawPlan(currentToken))

        assertEquals(false, res["success"])
        assertEquals(true, res["authorizationInvalidated"])
        assertEquals(true, res["partialFailure"])
        assertEquals("OS_CLEANUP_INCOMPLETE", res["errorCode"])
    }

    @Test
    fun testReplacePlanZeroFutureEventsExplicitlySucceeds() {
        val currentToken = store.getGenerationToken()
        val res = coordinator.replacePlan(sampleRawPlanWithEvents(currentToken, emptyList()))

        assertEquals(true, res["success"])
        assertEquals(true, res["authorizationInvalidated"])
        assertEquals(0, res["scheduledCount"])
        assertEquals(0, res["attemptedCount"])
        assertEquals(false, res["exactAlarmsUsed"])
        assertEquals(false, res["companionAlarmsUsed"])
        assertNull(res["partialFailure"])
    }

    @Test
    fun testDisableAlarmsFailedCleanupSurfacesFailureWithInvalidationPreserved() {
        scheduler.failCancel = true

        val res = coordinator.disableAlarms()

        assertEquals(false, res["success"])
        assertEquals(true, res["authorizationInvalidated"])
        assertEquals(true, res["partialFailure"])
        assertEquals("OS_CLEANUP_INCOMPLETE", res["errorCode"])
        assertFalse(store.isEnabled())
    }

    @Test
    fun testResetAllFailedCleanupSurfacesFailureWithInvalidationPreserved() {
        scheduler.failCancel = true

        val res = coordinator.resetAll()

        assertEquals(false, res["success"])
        assertEquals(true, res["authorizationInvalidated"])
        assertEquals(true, res["partialFailure"])
        assertEquals("OS_CLEANUP_INCOMPLETE", res["errorCode"])
        assertFalse(store.isEnabled())
        assertTrue(store.getConsumedLedgerSnapshot().isEmpty())
    }

    @Test
    fun testAuthorizeAndStartPlaybackSuppressionFailsClosedWithoutPhysicalStart() {
        val currentToken = store.getGenerationToken()

        stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )

        var physicalStarts = 0
        val res = coordinator.authorizeAndStartPlayback(
            token = currentToken,
            eventKey = fajrKey,
            nowEpochMillis = fajrTrigger + 100L,
            isSuppressed = { true }, // Suppressed by user or DND
            onPhysicalStart = {
                physicalStarts++
                true
            }
        )

        assertTrue(res is PlaybackStartResult.Suppressed)
        assertFalse(res.isFullyDurable)
        assertFalse(res.isStarted)
        assertEquals(0, physicalStarts)
    }

    @Test
    fun testAcquireVersusPhysicalStartContention() {
        val currentToken = store.getGenerationToken()

        // 1. Initial state: event is claimed exact before service starts
        stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )
        assertEquals(DeliveryState.EXACT_CLAIMED, store.getConsumedRecord(fajrKey)?.state)

        // 2. Manual lease is acquired concurrently before physical start
        val leaseRes = coordinator.acquireManualPlaybackLease("manual_req_1", "session_1")
        assertEquals(true, leaseRes["acquired"])
        assertTrue(coordinator.isManualPlaybackLeaseActive())

        // 3. authorizeAndStartPlayback runs under coordinator lock: must detect lease, suppress physical play,
        // and transition pre-start claim to MANUAL_SUPPRESSED with dedicated silent notification.
        var physicalStarted = false
        val res = coordinator.authorizeAndStartPlayback(
            token = currentToken,
            eventKey = fajrKey,
            nowEpochMillis = fajrTrigger + 50L,
            isSuppressed = { false },
            onPhysicalStart = {
                physicalStarted = true
                true
            }
        )

        assertTrue(res is PlaybackStartResult.Suppressed)
        assertFalse(physicalStarted)
        assertFalse(res.isStarted)
        assertFalse(res.isFullyDurable)

        // Exactly one silent notification posted, zero audible alert
        assertEquals(1, notifGateway.postedSilentManualAlerts.size)
        assertTrue(notifGateway.postedShortAlerts.isEmpty())
        assertEquals(DeliveryState.MANUAL_SUPPRESSED, store.getConsumedRecord(fajrKey)?.state)
    }

    @Test
    fun testLeaseHeldExactAndCompanionAndPreStartClaimAllZeroAudibleOneSilentTerminal() {
        val currentToken = store.getGenerationToken()

        // Acquire manual lease
        val leaseRes = coordinator.acquireManualPlaybackLease("manual_req_1", "session_1")
        assertEquals(true, leaseRes["acquired"])

        // 1. Exact alarm arrives while leased
        timeProvider.currentTime = fajrTrigger
        coordinator.handleAlarmTrigger(fajrKey, currentToken, AlarmTriggerType.EXACT)

        assertFalse(serviceGateway.running)
        assertTrue(notifGateway.postedShortAlerts.isEmpty())
        assertEquals(1, notifGateway.postedSilentManualAlerts.size)
        assertEquals(DeliveryState.MANUAL_SUPPRESSED, store.getConsumedRecord(fajrKey)?.state)

        // 2. Companion duplicate arrives 45s later: observes terminal MANUAL_SUPPRESSED and does not sound or repost
        timeProvider.currentTime = fajrTrigger + 45000L
        coordinator.handleAlarmTrigger(fajrKey, currentToken, AlarmTriggerType.COMPANION)

        assertFalse(serviceGateway.running)
        assertTrue(notifGateway.postedShortAlerts.isEmpty())
        assertEquals(1, notifGateway.postedSilentManualAlerts.size) // No duplicate repost!

        // 3. Service launch failure fallback branch while leased: never emits audible short alert
        val dhuhrKey = "360630:2026-10-07:dhuhr"
        val dhuhrTrigger = fajrTrigger + 3600000L
        val twoEventPlan = sampleRawPlanWithEvents(
            currentToken,
            listOf(
                mapOf(
                    "eventKey" to fajrKey,
                    "prayerKey" to "fajr",
                    "calculationCivilDate" to "2026-10-07",
                    "triggerEpochMillis" to fajrTrigger,
                    "voiceId" to "malmo_fajr",
                    "mode" to "full_adhan"
                ),
                mapOf(
                    "eventKey" to dhuhrKey,
                    "prayerKey" to "dhuhr",
                    "calculationCivilDate" to "2026-10-07",
                    "triggerEpochMillis" to dhuhrTrigger,
                    "voiceId" to "adam",
                    "mode" to "full_adhan"
                )
            )
        )
        val replRes = coordinator.replacePlan(twoEventPlan)
        val newToken = replRes["token"] as Long

        // Fail service launch
        serviceGateway.failStart = true
        timeProvider.currentTime = dhuhrTrigger
        coordinator.handleAlarmTrigger(dhuhrKey, newToken, AlarmTriggerType.EXACT)

        // Must NOT fall back to audible alert while leased!
        assertTrue(notifGateway.postedShortAlerts.isEmpty())
        assertEquals(DeliveryState.MANUAL_SUPPRESSED, store.getConsumedRecord(dhuhrKey)?.state)
        assertEquals(2, notifGateway.postedSilentManualAlerts.size) // 1 fajr + 1 dhuhr
    }

    @Test
    fun testLedgerWriteFailureCausesZeroSideEffects() {
        val currentToken = store.getGenerationToken()
        coordinator.acquireManualPlaybackLease("manual_req_1", "session_1")

        // Injected storage write failure
        storage.failWrites = true
        timeProvider.currentTime = fajrTrigger

        coordinator.handleAlarmTrigger(fajrKey, currentToken, AlarmTriggerType.EXACT)

        // Invariant: Fail-closed on ledger failure -> ZERO notification, ZERO service, ZERO audio!
        assertFalse(serviceGateway.running)
        assertTrue(notifGateway.postedShortAlerts.isEmpty())
        assertTrue(notifGateway.postedSilentManualAlerts.isEmpty())
    }

    @Test
    fun testFailedStopPreventsLeaseAcquisition() {
        // Native service is active and fails to stop
        serviceGateway.running = true
        serviceGateway.failStop = true

        val res = coordinator.acquireManualPlaybackLease("manual_req_1", "session_1")

        assertEquals(false, res["acquired"])
        assertEquals("NATIVE_SERVICE_STOP_FAILED", res["errorCode"])
        assertFalse(coordinator.isManualPlaybackLeaseActive())
        assertNull(coordinator.getManualPlaybackLease())
    }

    @Test
    fun testFailedNotificationCancellationPreventsLeaseAcquisition() {
        val currentToken = store.getGenerationToken()
        timeProvider.currentTime = fajrTrigger
        coordinator.handleAlarmTrigger(fajrKey, currentToken, AlarmTriggerType.EXACT)
        assertEquals(DeliveryState.EXACT_CLAIMED, store.getConsumedRecord(fajrKey)?.state)
        assertTrue(serviceGateway.running)

        // Emits short alert
        coordinator.handleServicePrestartFailure(currentToken, fajrKey, "audio_focus_denied", fajrTrigger + 1000L)
        assertTrue(notifGateway.postedShortAlerts.contains(fajrKey))

        // Notification cancellation fails
        notifGateway.failCancelNotification = true

        val res = coordinator.acquireManualPlaybackLease("manual_req_fail_cancel", "session_1")
        assertEquals(false, res["acquired"])
        assertEquals("NOTIFICATION_CANCEL_FAILED", res["errorCode"])
        assertFalse(coordinator.isManualPlaybackLeaseActive())
        assertNull(coordinator.getManualPlaybackLease())

        // Resolve cancellation failure and retry: succeeds and cancels notification
        notifGateway.failCancelNotification = false
        val retryRes = coordinator.acquireManualPlaybackLease("manual_req_fail_cancel", "session_1")
        assertEquals(true, retryRes["acquired"])
        assertTrue(coordinator.isManualPlaybackLeaseActive())
        assertTrue(notifGateway.cancelledNotifications.contains(fajrKey))
    }

    @Test
    fun testStaleOrRedundantReleaseCannotClearNewOwnerLease() {
        // Owner 1 acquires lease
        val res1 = coordinator.acquireManualPlaybackLease("req_1", "session_1")
        assertEquals(true, res1["acquired"])
        val token1 = res1["leaseToken"] as String

        // Owner 1 releases cleanly
        val rel1 = coordinator.releaseManualPlaybackLease(token1)
        assertEquals(true, rel1["released"])
        assertEquals(true, rel1["cleared"])
        assertFalse(coordinator.isManualPlaybackLeaseActive())

        // Owner 2 acquires new replacement lease
        val res2 = coordinator.acquireManualPlaybackLease("req_2", "session_2")
        assertEquals(true, res2["acquired"])
        val token2 = res2["leaseToken"] as String
        assertTrue(coordinator.isManualPlaybackLeaseActive())

        // Stale release from Owner 1 with token1 must be harmless and NOT clear Owner 2's lease!
        val staleRel = coordinator.releaseManualPlaybackLease(token1)
        assertEquals(true, staleRel["released"])
        assertEquals(false, staleRel["cleared"])
        assertEquals("token_mismatch", staleRel["reason"])

        // Owner 2 lease remains active
        assertTrue(coordinator.isManualPlaybackLeaseActive())
        assertEquals(token2, coordinator.getManualPlaybackLease()?.leaseToken)

        // Idempotent acquire for same session and requestId
        val idempRes = coordinator.acquireManualPlaybackLease("req_2", "session_2")
        assertEquals(true, idempRes["acquired"])
        assertEquals(token2, idempRes["leaseToken"])
        assertEquals(true, idempRes["idempotent"])

        // Busy rejection for different request while lease held
        val busyRes = coordinator.acquireManualPlaybackLease("req_3", "session_2")
        assertEquals(false, busyRes["acquired"])
        assertEquals("LEASE_BUSY", busyRes["errorCode"])
    }

    @Test
    fun testDisableAndResetInvalidatesPlansDoesNotClearManualLease() {
        coordinator.acquireManualPlaybackLease("req_1", "session_1")
        assertTrue(coordinator.isManualPlaybackLeaseActive())

        // disableAlarms invalidates plan but does NOT clear live manual lease early
        coordinator.disableAlarms()
        assertFalse(store.isEnabled())
        assertTrue(coordinator.isManualPlaybackLeaseActive())

        // resetAll resets store but does NOT clear live manual lease early
        coordinator.resetAll()
        assertFalse(store.isEnabled())
        assertTrue(store.getConsumedLedgerSnapshot().isEmpty())
        assertTrue(coordinator.isManualPlaybackLeaseActive())
    }

    @Test
    fun testUncertainEngineDetachDoesNotPrematurelyClearLeaseAndNewSessionIsBusy() {
        coordinator.acquireManualPlaybackLease("req_1", "session_1")
        assertTrue(coordinator.isManualPlaybackLeaseActive())

        // Engine detach occurs without confirmed silence/retirement: lease preserved
        // New engine session attaches and attempts to acquire without retiring old lease
        val busyRes = coordinator.acquireManualPlaybackLease("req_new", "session_2")
        assertEquals(false, busyRes["acquired"])
        assertEquals("LEASE_BUSY", busyRes["errorCode"])
        assertTrue(coordinator.isManualPlaybackLeaseActive())
    }

    @Test
    fun testReleaseDoesNotReplaySuppressedEvents() {
        val currentToken = store.getGenerationToken()
        val leaseRes = coordinator.acquireManualPlaybackLease("req_1", "session_1")
        val token = leaseRes["leaseToken"] as String

        // Event triggers and is silently suppressed
        timeProvider.currentTime = fajrTrigger
        coordinator.handleAlarmTrigger(fajrKey, currentToken, AlarmTriggerType.EXACT)
        assertEquals(DeliveryState.MANUAL_SUPPRESSED, store.getConsumedRecord(fajrKey)?.state)
        assertEquals(1, notifGateway.postedSilentManualAlerts.size)

        // Manual playback ends: lease is released
        val relRes = coordinator.releaseManualPlaybackLease(token)
        assertEquals(true, relRes["released"])
        assertEquals(true, relRes["cleared"])
        assertFalse(coordinator.isManualPlaybackLeaseActive())

        // Invariant: No automatic replay on release!
        assertFalse(serviceGateway.running)
        assertTrue(notifGateway.postedShortAlerts.isEmpty())

        // Future companion or alarm triggers observe terminal MANUAL_SUPPRESSED and drop
        coordinator.handleAlarmTrigger(fajrKey, currentToken, AlarmTriggerType.COMPANION)
        assertFalse(serviceGateway.running)
        assertTrue(notifGateway.postedShortAlerts.isEmpty())
        assertEquals(1, notifGateway.postedSilentManualAlerts.size)
    }

    @Test
    fun testDisableAlarmsCancelFailureThenRetrySucceedsWhenBoundarySucceeds() {
        scheduler.failCancel = true

        val res1 = coordinator.disableAlarms()
        assertEquals(false, res1["success"])
        assertEquals(true, res1["authorizationInvalidated"])
        assertEquals(true, res1["partialFailure"])
        assertEquals("OS_CLEANUP_INCOMPLETE", res1["errorCode"])
        assertTrue(store.hasPendingCleanup())

        // Retry while scheduler boundary still fails -> STILL fails!
        val res2 = coordinator.disableAlarms()
        assertEquals(false, res2["success"])
        assertEquals(true, res2["partialFailure"])
        assertEquals("OS_CLEANUP_INCOMPLETE", res2["errorCode"])
        assertTrue(store.hasPendingCleanup())

        // OS issue resolves -> Retry succeeds and clears pending cleanup!
        scheduler.failCancel = false
        val res3 = coordinator.disableAlarms()
        assertEquals(true, res3["success"])
        assertNull(res3["partialFailure"])
        assertFalse(store.hasPendingCleanup())
    }

    @Test
    fun testReopenStoreAndCoordinatorRetriesUnresolvedCancellations() {
        scheduler.failCancel = true

        val res1 = coordinator.disableAlarms()
        assertEquals(false, res1["success"])
        assertTrue(store.hasPendingCleanup())

        // Simulate process death / restart with fresh Store & Coordinator from same storage bytes:
        val newStore = PrayerAlarmStore(storage)
        assertTrue(newStore.hasPendingCleanup())
        assertEquals(1, newStore.getPendingCleanupEvents().size)
        assertEquals(fajrKey, newStore.getPendingCleanupEvents()[0].eventKey)

        val newScheduler = FakeAlarmScheduler()
        newScheduler.failCancel = true
        val newNotifGateway = FakeNotificationGateway()
        val newServiceGateway = FakeServiceGateway()
        val newCoordinator = PrayerAlarmCoordinator(
            store = newStore,
            timeProvider = timeProvider,
            alarmScheduler = newScheduler,
            notificationGateway = newNotifGateway,
            serviceGateway = newServiceGateway
        )

        // Retry from new coordinator fails because boundary fails, but original IDs are retried:
        val res2 = newCoordinator.disableAlarms()
        assertEquals(false, res2["success"])
        assertTrue(newScheduler.cancelled.isEmpty())
        assertTrue(newStore.hasPendingCleanup())

        // Boundary succeeds -> confirmed cancellation clears evidence:
        newScheduler.failCancel = false
        val res3 = newCoordinator.disableAlarms()
        assertEquals(true, res3["success"])
        assertTrue(newScheduler.cancelled.contains(fajrKey))
        assertTrue(newNotifGateway.cancelledNotifications.contains(fajrKey))
        assertFalse(newStore.hasPendingCleanup())
    }

    @Test
    fun testResetAllCancelFailureThenRetryAndReopenRetainsUnresolvedEvidence() {
        scheduler.failCancel = true

        val res1 = coordinator.resetAll()
        assertEquals(false, res1["success"])
        assertEquals("OS_CLEANUP_INCOMPLETE", res1["errorCode"])
        assertTrue(store.hasPendingCleanup())

        // Reopen store from storage bytes: evidence is preserved across reset
        val newStore = PrayerAlarmStore(storage)
        assertTrue(newStore.hasPendingCleanup())
        assertEquals(1, newStore.getPendingCleanupEvents().size)

        val newScheduler = FakeAlarmScheduler()
        val newNotifGateway = FakeNotificationGateway()
        val newServiceGateway = FakeServiceGateway()
        val newCoordinator = PrayerAlarmCoordinator(
            store = newStore,
            timeProvider = timeProvider,
            alarmScheduler = newScheduler,
            notificationGateway = newNotifGateway,
            serviceGateway = newServiceGateway
        )

        val res2 = newCoordinator.resetAll()
        assertEquals(true, res2["success"])
        assertTrue(newScheduler.cancelled.contains(fajrKey))
        assertFalse(newStore.hasPendingCleanup())
    }

    @Test
    fun testReplacePlanFailedOldPlanCancellationPreservesOldEventsForLaterCleanup() {
        val currentToken = store.getGenerationToken()
        val dhuhrKey = "360630:2026-10-07:dhuhr"
        val dhuhrTrigger = fajrTrigger + 3600000L
        val plan2 = sampleRawPlanWithEvents(
            currentToken,
            listOf(
                mapOf(
                    "eventKey" to dhuhrKey,
                    "prayerKey" to "dhuhr",
                    "calculationCivilDate" to "2026-10-07",
                    "triggerEpochMillis" to dhuhrTrigger,
                    "voiceId" to "adam",
                    "mode" to "full_adhan"
                )
            )
        )

        scheduler.failCancel = true
        val repRes = coordinator.replacePlan(plan2)
        assertEquals(false, repRes["success"])
        assertEquals("OS_CLEANUP_INCOMPLETE", repRes["errorCode"])
        assertEquals(true, repRes["partialFailure"])

        // Old event is preserved in pending cleanup, but new plan is active
        assertTrue(store.hasPendingCleanup())
        assertEquals(1, store.getPendingCleanupEvents().size)
        assertEquals(fajrKey, store.getPendingCleanupEvents()[0].eventKey)
        assertEquals(dhuhrKey, store.getActivePlan()?.events?.get(0)?.eventKey)

        // Later disable resolves boundary and cleans up BOTH old and new plan events
        scheduler.failCancel = false
        val disRes = coordinator.disableAlarms()
        assertEquals(true, disRes["success"])
        assertTrue(scheduler.cancelled.contains(fajrKey))
        assertTrue(scheduler.cancelled.contains(dhuhrKey))
        assertFalse(store.hasPendingCleanup())
    }

    @Test
    fun testReplacePlanMixedEventsPairedRegistrationCountsCorrectly() {
        val currentToken = store.getGenerationToken()
        val dhuhrKey = "360630:2026-10-07:dhuhr"
        val dhuhrTrigger = fajrTrigger + 3600000L
        val twoEventPlan = sampleRawPlanWithEvents(
            currentToken,
            listOf(
                mapOf(
                    "eventKey" to fajrKey,
                    "prayerKey" to "fajr",
                    "calculationCivilDate" to "2026-10-07",
                    "triggerEpochMillis" to fajrTrigger,
                    "voiceId" to "malmo_fajr",
                    "mode" to "full_adhan"
                ),
                mapOf(
                    "eventKey" to dhuhrKey,
                    "prayerKey" to "dhuhr",
                    "calculationCivilDate" to "2026-10-07",
                    "triggerEpochMillis" to dhuhrTrigger,
                    "voiceId" to "adam",
                    "mode" to "full_adhan"
                )
            )
        )

        // Exact succeeds for fajr only; companion succeeds for dhuhr only
        scheduler.failExactEvents.add(dhuhrKey)
        scheduler.failCompanionEvents.add(fajrKey)

        val res = coordinator.replacePlan(twoEventPlan)

        assertEquals(false, res["success"])
        assertEquals(true, res["partialFailure"])
        assertEquals("ALARM_SCHEDULING_INCOMPLETE", res["errorCode"])
        assertEquals(1, res["exactScheduledCount"])
        assertEquals(1, res["companionScheduledCount"])
        assertEquals(2, res["attemptedCount"])
        // Crucial invariant: ZERO events had BOTH required registrations!
        assertEquals(0, res["scheduledCount"])
    }

    @Test
    fun testReplacePlanCompanionOnlyWhenExactDeniedCountsCorrectly() {
        scheduler.canScheduleExact = false
        val currentToken = store.getGenerationToken()
        val dhuhrKey = "360630:2026-10-07:dhuhr"
        val dhuhrTrigger = fajrTrigger + 3600000L
        val twoEventPlan = sampleRawPlanWithEvents(
            currentToken,
            listOf(
                mapOf(
                    "eventKey" to fajrKey,
                    "prayerKey" to "fajr",
                    "calculationCivilDate" to "2026-10-07",
                    "triggerEpochMillis" to fajrTrigger,
                    "voiceId" to "malmo_fajr",
                    "mode" to "full_adhan"
                ),
                mapOf(
                    "eventKey" to dhuhrKey,
                    "prayerKey" to "dhuhr",
                    "calculationCivilDate" to "2026-10-07",
                    "triggerEpochMillis" to dhuhrTrigger,
                    "voiceId" to "adam",
                    "mode" to "full_adhan"
                )
            )
        )

        // Fajr companion succeeds; dhuhr companion fails
        scheduler.failCompanionEvents.add(dhuhrKey)

        val res = coordinator.replacePlan(twoEventPlan)

        assertEquals(false, res["success"])
        assertEquals(true, res["partialFailure"])
        assertEquals("ALARM_SCHEDULING_INCOMPLETE", res["errorCode"])
        assertEquals(0, res["exactScheduledCount"])
        assertEquals(1, res["companionScheduledCount"])
        assertEquals(2, res["attemptedCount"])
        // Inexact mode: 1 event successfully registered
        assertEquals(1, res["scheduledCount"])
    }

    @Test
    fun testStorageWriteFailureBeforeCASCausesZeroOSSideEffects() {
        storage.failWrites = true
        val currentToken = store.getGenerationToken()

        val res = coordinator.replacePlan(sampleRawPlan(currentToken))

        assertEquals(false, res["success"])
        assertEquals("STORAGE_PERSISTENCE_FAILURE", res["errorCode"])
        assertTrue(scheduler.scheduledExact.isEmpty())
        assertTrue(scheduler.scheduledCompanion.isEmpty())
    }

    @Test
    fun testFailedAckRetainsRetryableCleanupAfterReopen() {
        // Disable initial setup cleanly
        coordinator.disableAlarms()

        // Install new plan using actual store token after disable
        val actualToken = store.getGenerationToken()
        val replaceResult = store.replacePlan(actualToken, samplePlan(actualToken), baseTime)
        assertTrue(replaceResult is ReplacePlanResult.Success)
        assertNotNull(store.getActivePlan())
        assertEquals(1, store.getActivePlan()?.events?.size)

        // Inject storage write failure specifically during cleanup ack by creating a hooked scheduler:
        val hookScheduler = object : AlarmSchedulerGateway by scheduler {
            override fun cancelAlarms(event: PrayerEventRecord): Boolean {
                scheduler.cancelAlarms(event)
                // Boundary cancels, but storage write will fail during ack
                storage.failWrites = true
                return true
            }
        }
        val coordinatorWithHook = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = hookScheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        val res = coordinatorWithHook.disableAlarms()
        assertEquals(false, res["success"])
        assertEquals("OS_CLEANUP_INCOMPLETE", res["errorCode"])
        assertTrue(store.hasPendingCleanup())

        // Reopen fresh instance: pending cleanup was retained
        storage.failWrites = false
        val reopenedStore = PrayerAlarmStore(storage)
        assertTrue(reopenedStore.hasPendingCleanup())

        val reopenedCoordinator = PrayerAlarmCoordinator(
            store = reopenedStore,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )
        val res2 = reopenedCoordinator.disableAlarms()
        assertEquals(true, res2["success"])
        assertFalse(reopenedStore.hasPendingCleanup())
    }

    @Test
    fun testFailedResetPendingCleanupRetainsShortNotificationAndAcquireManualLeaseFailsUntilCancelled() {
        val currentToken = store.getGenerationToken()
        timeProvider.currentTime = fajrTrigger

        // 1. Real delivery -> SHORT via OS failure boundary (e.g. audio focus denied)
        coordinator.handleAlarmTrigger(fajrKey, currentToken, AlarmTriggerType.EXACT)
        assertEquals(DeliveryState.EXACT_CLAIMED, store.getConsumedRecord(fajrKey)?.state)
        val handled = coordinator.handleServicePrestartFailure(
            token = currentToken,
            eventKey = fajrKey,
            reason = "audio_focus_denied",
            nowEpochMillis = fajrTrigger + 1000L
        )
        assertTrue(handled)
        assertEquals(DeliveryState.SHORT_DELIVERED, store.getConsumedRecord(fajrKey)?.state)
        assertTrue(notifGateway.postedShortAlerts.contains(fajrKey))
        assertTrue(notifGateway.activeShortAlerts.contains(fajrKey))

        // 2. Reset attempted, but notification cancellation fails at OS boundary
        notifGateway.failCancelNotification = true
        val resetRes = coordinator.resetAll()
        assertEquals(false, resetRes["success"])
        assertEquals(true, resetRes["partialFailure"])
        assertEquals("OS_CLEANUP_INCOMPLETE", resetRes["errorCode"])
        assertTrue(store.hasPendingCleanup())
        assertEquals(1, store.getPendingCleanupEvents().size)

        // 3. New process starts: new Store from same storage driver, new Coordinator instance
        val newStore = PrayerAlarmStore(storage)
        assertTrue(newStore.hasPendingCleanup())
        assertTrue(newStore.getConsumedLedgerSnapshot().isEmpty()) // Ledger was wiped by reset
        assertNull(newStore.getActivePlan()) // Active plan was wiped by reset

        // SAME OS fake where ongoing short notification persists and notification cancel still fails
        val newScheduler = FakeAlarmScheduler()
        val newCoordinator = PrayerAlarmCoordinator(
            store = newStore,
            timeProvider = timeProvider,
            alarmScheduler = newScheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        // 4. Manual lease acquire must FAIL when notification cancel still fails
        val acquireRes = newCoordinator.acquireManualPlaybackLease("quran_manual_req", "session_1")
        assertEquals(false, acquireRes["acquired"])
        assertEquals("NOTIFICATION_CANCEL_FAILED", acquireRes["errorCode"])
        assertFalse(newCoordinator.isManualPlaybackLeaseActive())
        assertTrue(notifGateway.activeShortAlerts.contains(fajrKey)) // old Short alert persists in active OS alerts
        assertEquals(1, notifGateway.postedShortAlerts.size) // history stays 1

        // 5. Retry with OS cancellation resolved: removes old Short sound THEN grants lease
        notifGateway.failCancelNotification = false
        val retryRes = newCoordinator.acquireManualPlaybackLease("quran_manual_req", "session_1")
        assertEquals(true, retryRes["acquired"])
        assertTrue(newCoordinator.isManualPlaybackLeaseActive())
        assertFalse(notifGateway.activeShortAlerts.contains(fajrKey)) // active Short sound confirmed removed
        assertEquals(1, notifGateway.postedShortAlerts.size) // history stays 1 to prove no replay
        assertTrue(notifGateway.cancelledNotifications.contains(fajrKey))

        // Invariant: notification cancellation does NOT prematurely ack pending cleanup in store;
        // alarm cleanup is separately verified/acked via processPendingCleanup
        assertTrue(newStore.hasPendingCleanup())
    }

    @Test
    fun testGetStateExposesPendingCleanupCountAcrossPartialCleanupReopenConfirmedAckAndLegacyStorage() {
        // Initial state with active plan: 0 pending cleanup
        val stateInitial = coordinator.getState()
        assertEquals(0, stateInitial["pendingCleanupCount"])

        // 1. Partial cleanup failure leaves pending cleanup count > 0
        scheduler.failCancel = true
        val disRes = coordinator.disableAlarms()
        assertEquals(false, disRes["success"])
        assertEquals("OS_CLEANUP_INCOMPLETE", disRes["errorCode"])

        val stateAfterPartial = coordinator.getState()
        assertEquals(1, stateAfterPartial["pendingCleanupCount"])

        // 2. Fresh reopen from same driver preserves pendingCleanupCount > 0
        val reopenedStore = PrayerAlarmStore(storage)
        val reopenedCoordinator = PrayerAlarmCoordinator(
            store = reopenedStore,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )
        val stateReopened = reopenedCoordinator.getState()
        assertEquals(1, stateReopened["pendingCleanupCount"])

        // 3. After confirmed OS cancellation and ack: pendingCleanupCount returns to 0
        scheduler.failCancel = false
        val disRes2 = reopenedCoordinator.disableAlarms()
        assertEquals(true, disRes2["success"])

        val stateAfterConfirmedAck = reopenedCoordinator.getState()
        assertEquals(0, stateAfterConfirmedAck["pendingCleanupCount"])

        // 4. Legacy storage JSON without pendingCleanup field: pendingCleanupCount is 0
        val legacyStorage = InMemoryStorageDriver()
        legacyStorage.setRaw("{\"enabled\":false,\"generationToken\":5,\"consumedLedger\":[]}")
        val legacyStore = PrayerAlarmStore(legacyStorage)
        val legacyCoordinator = PrayerAlarmCoordinator(
            store = legacyStore,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )
        val legacyState = legacyCoordinator.getState()
        assertEquals(0, legacyState["pendingCleanupCount"])
    }
}
