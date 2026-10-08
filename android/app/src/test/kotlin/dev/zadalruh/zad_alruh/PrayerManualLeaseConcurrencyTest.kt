package dev.zadalruh.zad_alruh

import dev.zadalruh.zad_alruh.alarm.AlarmProcessingOutcome
import dev.zadalruh.zad_alruh.alarm.AlarmTriggerType
import dev.zadalruh.zad_alruh.alarm.DeliveryState
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmCoordinator
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmStore
import dev.zadalruh.zad_alruh.alarm.PrayerEventRecord
import dev.zadalruh.zad_alruh.alarm.PrayerPlan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

class GatedNotificationGateway : FakeNotificationGateway() {
    val postShortAlertStartedLatch = CountDownLatch(1)
    val allowPostShortAlertLatch = CountDownLatch(1)
    var gatePostShortAlert: Boolean = false

    override fun postShortAlert(
        eventKey: String,
        prayerKey: String,
        cityNameAr: String,
        voiceId: String
    ): Boolean {
        if (gatePostShortAlert) {
            postShortAlertStartedLatch.countDown()
            val allowed = allowPostShortAlertLatch.await(5, TimeUnit.SECONDS)
            if (!allowed) throw IllegalStateException("Timed out waiting for postShortAlert gate release")
        }
        return super.postShortAlert(eventKey, prayerKey, cityNameAr, voiceId)
    }
}

class GatedServiceGateway : FakeServiceGateway() {
    val stopServiceStartedLatch = CountDownLatch(1)
    val allowStopServiceLatch = CountDownLatch(1)
    var gateStopService: Boolean = false

    override fun stopAdhanPlaybackService(): Boolean {
        if (gateStopService) {
            stopServiceStartedLatch.countDown()
            val allowed = allowStopServiceLatch.await(5, TimeUnit.SECONDS)
            if (!allowed) throw IllegalStateException("Timed out waiting for stopAdhanPlaybackService gate release")
        }
        return super.stopAdhanPlaybackService()
    }
}

class PrayerManualLeaseConcurrencyTest {

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

    @Test
    fun testPrestartNotificationPostBoundaryHeldWhileAcquireRacesCancelsOwnedAlert() {
        val storage = InMemoryStorageDriver()
        val store = PrayerAlarmStore(storage)
        store.replacePlan(1L, samplePlan(1L), baseTime)
        val token = store.getGenerationToken()

        val scheduler = FakeAlarmScheduler()
        val notifGateway = GatedNotificationGateway()
        val serviceGateway = FakeServiceGateway()
        val timeProvider = MutableTimeProvider(fajrTrigger)

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        // 1. Advance state machine to EXACT_CLAIMED
        val outcome = coordinator.stateMachine.processAlarmTrigger(
            intentToken = token,
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

        val executor = Executors.newFixedThreadPool(2)
        try {
            // Enable gating on notification post boundary
            notifGateway.gatePostShortAlert = true

            // Thread A: runs pre-start failure handler which posts short alert
            val failureFuture = executor.submit<Boolean> {
                coordinator.handleServicePrestartFailure(
                    token = token,
                    eventKey = fajrKey,
                    reason = "media_player_prepare_failed",
                    nowEpochMillis = fajrTrigger + 500L
                )
            }

            // Wait until Thread A enters postShortAlert boundary while holding coordinatorLock
            val enteredPost = notifGateway.postShortAlertStartedLatch.await(5, TimeUnit.SECONDS)
            assertTrue("Thread A must reach postShortAlert boundary", enteredPost)

            // Thread B: attempts to acquire manual lease concurrently (must block on coordinatorLock)
            val acquireAttemptedLatch = CountDownLatch(1)
            val acquireFuture = executor.submit<Map<String, Any?>> {
                acquireAttemptedLatch.countDown()
                coordinator.acquireManualPlaybackLease("concurrent-req-post-race", "session-race-1")
            }

            // Wait until Thread B actually attempts coordinator call
            val attempted = acquireAttemptedLatch.await(5, TimeUnit.SECONDS)
            assertTrue("Thread B must attempt acquire while post gate is held", attempted)

            // While OS gate still CLOSED, assert racing future is genuinely blocked on coordinatorLock
            assertThrows(TimeoutException::class.java) {
                acquireFuture.get(100, TimeUnit.MILLISECONDS)
            }

            // Release Thread A from gateway post boundary
            notifGateway.allowPostShortAlertLatch.countDown()

            val failureResult = failureFuture.get(5, TimeUnit.SECONDS)
            assertTrue("Prestart failure must complete successfully", failureResult)

            // Now Thread B proceeds: stops service, cancels owned short notification, and grants lease
            val acquireResult = acquireFuture.get(5, TimeUnit.SECONDS)
            assertEquals(true, acquireResult["acquired"])
            assertNotNull(acquireResult["leaseToken"])
            assertTrue(coordinator.isManualPlaybackLeaseActive())

            // INVARIANTS:
            // 1. Prestart failure posted the short alert
            assertEquals(listOf(fajrKey), notifGateway.postedShortAlerts)
            // 2. But upon grant, owned cancellation was accepted: zero audible owned output remains
            assertTrue(
                "Owned prayer notification cancellation must be accepted before manual lease grant",
                notifGateway.cancelledNotifications.contains(fajrKey)
            )
            assertFalse(notifGateway.activeShortAlerts.contains(fajrKey))
            // 3. Ledger records SHORT_DELIVERED (truth preserved without rewrite)
            assertEquals(DeliveryState.SHORT_DELIVERED, store.getConsumedRecord(fajrKey)?.state)
        } finally {
            notifGateway.allowPostShortAlertLatch.countDown()
            executor.shutdownNow()
            executor.awaitTermination(5, TimeUnit.SECONDS)
        }
    }

    @Test
    fun testServiceStopBoundaryHeldWhileFailureRacesYieldsManualSuppressed() {
        val storage = InMemoryStorageDriver()
        val store = PrayerAlarmStore(storage)
        store.replacePlan(1L, samplePlan(1L), baseTime)
        val token = store.getGenerationToken()

        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = GatedServiceGateway()
        val timeProvider = MutableTimeProvider(fajrTrigger)

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        // 1. Advance state machine to EXACT_CLAIMED
        coordinator.stateMachine.processAlarmTrigger(
            intentToken = token,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )

        val executor = Executors.newFixedThreadPool(2)
        try {
            // Enable gating on service stop boundary
            serviceGateway.gateStopService = true

            // Thread A: calls acquireManualPlaybackLease which enters service stop under coordinatorLock
            val acquireFuture = executor.submit<Map<String, Any?>> {
                coordinator.acquireManualPlaybackLease("concurrent-req-stop-race", "session-race-2")
            }

            // Wait until Thread A reaches stopAdhanPlaybackService while holding coordinatorLock
            val enteredStop = serviceGateway.stopServiceStartedLatch.await(5, TimeUnit.SECONDS)
            assertTrue("Thread A must reach stop service boundary under lock", enteredStop)

            // Thread B: pre-start failure races concurrently (must block on coordinatorLock)
            val failureAttemptedLatch = CountDownLatch(1)
            val failureFuture = executor.submit<Boolean> {
                failureAttemptedLatch.countDown()
                coordinator.handleServicePrestartFailure(
                    token = token,
                    eventKey = fajrKey,
                    reason = "audio_focus_denied",
                    nowEpochMillis = fajrTrigger + 500L
                )
            }

            // Wait until Thread B actually attempts coordinator call
            val attempted = failureAttemptedLatch.await(5, TimeUnit.SECONDS)
            assertTrue("Thread B must attempt failure handler while stop gate is held", attempted)

            // While OS gate still CLOSED, assert racing failureFuture is genuinely blocked on coordinatorLock
            assertThrows(TimeoutException::class.java) {
                failureFuture.get(100, TimeUnit.MILLISECONDS)
            }

            // Release Thread A from gateway stop boundary
            serviceGateway.allowStopServiceLatch.countDown()

            val acquireResult = acquireFuture.get(5, TimeUnit.SECONDS)
            assertEquals(true, acquireResult["acquired"])
            assertTrue(coordinator.isManualPlaybackLeaseActive())

            // Thread B now unblocks, observes lease is active under coordinatorLock,
            // consumes as MANUAL_SUPPRESSED, emits ONE silent notice, and ZERO short alerts
            val failureResult = failureFuture.get(5, TimeUnit.SECONDS)
            assertTrue(failureResult)

            // INVARIANTS:
            // 1. Consumed as MANUAL_SUPPRESSED
            assertEquals(DeliveryState.MANUAL_SUPPRESSED, store.getConsumedRecord(fajrKey)?.state)
            // 2. Emits exactly ONE silent notification
            assertEquals(listOf(fajrKey), notifGateway.postedSilentManualAlerts)
            // 3. ZERO audible short alert
            assertTrue("Must NOT emit any short audible alert when lease granted", notifGateway.postedShortAlerts.isEmpty())
        } finally {
            serviceGateway.allowStopServiceLatch.countDown()
            executor.shutdownNow()
            executor.awaitTermination(5, TimeUnit.SECONDS)
        }
    }

    @Test
    fun testNotificationCancellationFailureDeniesLeaseAndRetainsTruth() {
        val storage = InMemoryStorageDriver()
        val store = PrayerAlarmStore(storage)
        store.replacePlan(1L, samplePlan(1L), baseTime)
        val token = store.getGenerationToken()

        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()
        val timeProvider = MutableTimeProvider(fajrTrigger)

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        // 1. Prestart failure occurs, posting short notification
        coordinator.stateMachine.processAlarmTrigger(
            intentToken = token,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )
        val handled = coordinator.handleServicePrestartFailure(
            token = token,
            eventKey = fajrKey,
            reason = "start_foreground_failed",
            nowEpochMillis = fajrTrigger + 200L
        )
        assertTrue(handled)
        assertEquals(DeliveryState.SHORT_DELIVERED, store.getConsumedRecord(fajrKey)?.state)
        assertEquals(listOf(fajrKey), notifGateway.postedShortAlerts)

        // 2. Cancellation failure injected at OS boundary
        notifGateway.failCancelNotification = true

        val acquireResult = coordinator.acquireManualPlaybackLease("req-cancel-fail", "session-fail")

        // INVARIANTS:
        // Lease denied with stable error code
        assertEquals(false, acquireResult["acquired"])
        assertEquals("NOTIFICATION_CANCEL_FAILED", acquireResult["errorCode"])
        assertFalse(coordinator.isManualPlaybackLeaseActive())
        assertNull(coordinator.getManualPlaybackLease())

        // Retains truth: ledger state remains SHORT_DELIVERED without corruption
        assertEquals(DeliveryState.SHORT_DELIVERED, store.getConsumedRecord(fajrKey)?.state)

        // 3. Once cancellation failure resolves, lease acquisition succeeds and notification is cancelled
        notifGateway.failCancelNotification = false
        val retryResult = coordinator.acquireManualPlaybackLease("req-cancel-fail", "session-fail")
        assertEquals(true, retryResult["acquired"])
        assertTrue(coordinator.isManualPlaybackLeaseActive())
        assertTrue(notifGateway.cancelledNotifications.contains(fajrKey))
        assertFalse(notifGateway.activeShortAlerts.contains(fajrKey))
    }
}
