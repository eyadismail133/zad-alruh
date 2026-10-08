package dev.zadalruh.zad_alruh

import dev.zadalruh.zad_alruh.alarm.AlarmProcessingOutcome
import dev.zadalruh.zad_alruh.alarm.AlarmSchedulerGateway
import dev.zadalruh.zad_alruh.alarm.AlarmTriggerType
import dev.zadalruh.zad_alruh.alarm.ConsumedRecord
import dev.zadalruh.zad_alruh.alarm.DeliveryState
import dev.zadalruh.zad_alruh.alarm.NotificationGateway
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmCoordinator
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmStore
import dev.zadalruh.zad_alruh.alarm.PrayerDeliveryStateMachine
import dev.zadalruh.zad_alruh.alarm.PrayerEventRecord
import dev.zadalruh.zad_alruh.alarm.PrayerPlan
import dev.zadalruh.zad_alruh.alarm.ServiceGateway
import dev.zadalruh.zad_alruh.alarm.TimeProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

class FakeAlarmScheduler : AlarmSchedulerGateway {
    var canScheduleExact: Boolean = true
    val scheduledExact = mutableListOf<String>()
    val scheduledExactTimes = mutableMapOf<String, Long>()
    val scheduledCompanion = mutableListOf<String>()
    val scheduledCompanionTimes = mutableMapOf<String, Long>()
    val cancelled = mutableListOf<String>()
    var failExact: Boolean = false
    var failCompanion: Boolean = false
    var failCancel: Boolean = false

    override fun canScheduleExactAlarms(): Boolean = canScheduleExact

    override fun scheduleExact(eventKey: String, triggerEpochMillis: Long, token: Long, requestCode: Int): Boolean {
        if (failExact) return false
        scheduledExact.add(eventKey)
        scheduledExactTimes[eventKey] = triggerEpochMillis
        return true
    }

    override fun scheduleCompanion(eventKey: String, triggerEpochMillis: Long, token: Long, requestCode: Int): Boolean {
        if (failCompanion) return false
        scheduledCompanion.add(eventKey)
        scheduledCompanionTimes[eventKey] = triggerEpochMillis
        return true
    }

    override fun cancelAlarms(event: PrayerEventRecord): Boolean {
        if (failCancel) return false
        cancelled.add(event.eventKey)
        return true
    }
}

open class FakeNotificationGateway : NotificationGateway {
    var notifEnabled: Boolean = true
    var playbackStatusBlocked: Boolean = false
    var dndOrSilent: Boolean = false
    val blockedVoiceChannels = mutableSetOf<String>()
    val postedShortAlerts = mutableListOf<String>()
    val cancelledNotifications = mutableListOf<String>()
    var failPostShortAlert: Boolean = false
    var failCancelNotification: Boolean = false

    override fun areNotificationsEnabled(): Boolean = notifEnabled
    override fun isPlaybackStatusChannelBlocked(): Boolean = playbackStatusBlocked
    override fun isVoiceChannelBlocked(voiceId: String): Boolean = blockedVoiceChannels.contains(voiceId)
    override fun isManualSilentChannelBlocked(): Boolean = manualSilentChannelBlocked
    override fun isDndOrSilentActive(): Boolean = dndOrSilent

    var manualSilentChannelBlocked: Boolean = false
    val postedSilentManualAlerts = mutableListOf<String>()
    var failPostSilentAlert: Boolean = false

    override fun postShortAlert(
        eventKey: String,
        prayerKey: String,
        cityNameAr: String,
        voiceId: String
    ): Boolean {
        if (failPostShortAlert) return false
        postedShortAlerts.add(eventKey)
        return true
    }

    override fun postSilentManualSuppressedAlert(
        eventKey: String,
        prayerKey: String,
        cityNameAr: String
    ): Boolean {
        if (failPostSilentAlert) return false
        postedSilentManualAlerts.add(eventKey)
        return true
    }

    override fun cancelEventNotification(eventKey: String): Boolean {
        if (failCancelNotification) return false
        cancelledNotifications.add(eventKey)
        return true
    }
}

open class FakeServiceGateway : ServiceGateway {
    var running: Boolean = false
    val startedEvents = mutableListOf<String>()
    var failStart: Boolean = false
    var failStop: Boolean = false

    override fun isServiceRunning(): Boolean = running

    override fun startAdhanPlaybackService(eventKey: String, token: Long): Boolean {
        if (failStart) return false
        startedEvents.add(eventKey)
        running = true
        return true
    }

    override fun stopAdhanPlaybackService(): Boolean {
        if (failStop) return false
        running = false
        return true
    }
}

class MutableTimeProvider(var currentTime: Long) : TimeProvider {
    override fun now(): Long = currentTime
}

class PrayerDeliveryStateMachineTest {

    private lateinit var storage: InMemoryStorageDriver
    private lateinit var store: PrayerAlarmStore
    private lateinit var stateMachine: PrayerDeliveryStateMachine

    private val baseTime = 1760000000000L
    private val fajrKey = "360630:2026-10-07:fajr"
    private val fajrTrigger = baseTime + 60000L // 1 minute from baseTime

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

    @Before
    fun setUp() {
        storage = InMemoryStorageDriver()
        store = PrayerAlarmStore(storage)
        stateMachine = PrayerDeliveryStateMachine(store)

        // Install enabled plan at token 1 -> increments to 2
        store.replacePlan(expectedToken = 1L, newPlan = samplePlan(1L), nowEpochMillis = baseTime)
    }

    @Test
    fun testExactFirstDeliveryPreventsCompanionDoubleSound() {
        val currentToken = store.getGenerationToken()

        // 1. Exact alarm fires on time
        val outcomeExact = stateMachine.processAlarmTrigger(
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

        assertTrue(outcomeExact is AlarmProcessingOutcome.StartFullAdhan)
        assertEquals(DeliveryState.EXACT_CLAIMED, store.getConsumedRecord(fajrKey)?.state)

        // 2. Service starts, marks play claim before start, then marks full started
        val claimed = stateMachine.markPlayClaimedBeforeStart(currentToken, fajrKey, fajrTrigger + 100L)
        assertTrue(claimed)
        assertEquals(DeliveryState.PLAY_CLAIMED, store.getConsumedRecord(fajrKey)?.state)

        val fullStarted = stateMachine.markFullPlaybackStarted(currentToken, fajrKey, fajrTrigger + 200L)
        assertTrue(fullStarted)
        assertEquals(DeliveryState.FULL_CONSUMED, store.getConsumedRecord(fajrKey)?.state)

        // 3. Companion alarm fires 10 seconds later
        val outcomeCompanion = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.COMPANION,
            nowEpochMillis = fajrTrigger + 10000L,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = true
        )

        // MUST drop already delivered; zero short sound!
        assertEquals(AlarmProcessingOutcome.AlreadyDelivered, outcomeCompanion)
        assertEquals(DeliveryState.FULL_CONSUMED, store.getConsumedRecord(fajrKey)?.state)
    }

    @Test
    fun testCompanionFirstDeliveryWhenExactPermissionDeniedPreventsDoubleSound() {
        val currentToken = store.getGenerationToken()

        // 1. Companion fires when exact permission is denied
        val outcomeCompanion = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.COMPANION,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = false, // denied!
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )

        assertTrue(outcomeCompanion is AlarmProcessingOutcome.DeliverShortFallback)
        assertEquals(DeliveryState.SHORT_DELIVERED, store.getConsumedRecord(fajrKey)?.state)

        // 2. Exact alarm somehow fires later
        val outcomeExact = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger + 5000L,
            canScheduleExactAlarms = false,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )

        // MUST drop already delivered; zero second sound!
        assertEquals(AlarmProcessingOutcome.AlreadyDelivered, outcomeExact)
        assertEquals(DeliveryState.SHORT_DELIVERED, store.getConsumedRecord(fajrKey)?.state)
    }

    @Test
    fun testConcurrentExactAndCompanionFireProducesExactlyOneDelivery() {
        val currentToken = store.getGenerationToken()
        val executor = Executors.newFixedThreadPool(2)
        val latch = CountDownLatch(1)
        val fullStarts = AtomicInteger(0)
        val shortFallbacks = AtomicInteger(0)
        val drops = AtomicInteger(0)

        val taskExact = Runnable {
            latch.await()
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
            when (outcome) {
                is AlarmProcessingOutcome.StartFullAdhan -> fullStarts.incrementAndGet()
                is AlarmProcessingOutcome.DeliverShortFallback -> shortFallbacks.incrementAndGet()
                else -> drops.incrementAndGet()
            }
        }

        val taskCompanion = Runnable {
            latch.await()
            val outcome = stateMachine.processAlarmTrigger(
                intentToken = currentToken,
                eventKey = fajrKey,
                alarmType = AlarmTriggerType.COMPANION,
                nowEpochMillis = fajrTrigger,
                canScheduleExactAlarms = true,
                notificationsAllowed = true,
                statusChannelBlocked = false,
                dndOrSilentSuppresses = false,
                isServiceCurrentlyActive = false
            )
            when (outcome) {
                is AlarmProcessingOutcome.StartFullAdhan -> fullStarts.incrementAndGet()
                is AlarmProcessingOutcome.DeliverShortFallback -> shortFallbacks.incrementAndGet()
                else -> drops.incrementAndGet()
            }
        }

        val f1 = executor.submit(taskExact)
        val f2 = executor.submit(taskCompanion)
        latch.countDown()
        f1.get()
        f2.get()
        executor.shutdown()

        // Exactly one sound dispatch must occur!
        val totalDeliveries = fullStarts.get() + shortFallbacks.get()
        assertEquals(1, totalDeliveries)
        assertEquals(1, drops.get())
    }

    @Test
    fun testAudioFocusFailureTriggersOneShortFallbackWithinLatenessWindow() {
        val currentToken = store.getGenerationToken()

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

        // Focus fails in service at fajrTrigger + 10s (within 5min window)
        val fallbackAllowed = stateMachine.handleServiceStartupFailure(
            expectedToken = currentToken,
            eventKey = fajrKey,
            reason = "audio_focus_denied",
            nowEpochMillis = fajrTrigger + 10000L
        )

        assertTrue(fallbackAllowed)
        assertEquals(DeliveryState.SHORT_DELIVERED, store.getConsumedRecord(fajrKey)?.state)

        // Subsequent companion retry drops
        val retryOutcome = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.COMPANION,
            nowEpochMillis = fajrTrigger + 20000L,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )
        assertEquals(AlarmProcessingOutcome.AlreadyDelivered, retryOutcome)
    }

    @Test
    fun testProcessDeathAfterExactClaimAllowsShortFallbackOnceAndNeverReplaysFull() {
        val currentToken = store.getGenerationToken()

        // Exact claims, then process dies before service starts
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

        // Process is dead (isServiceCurrentlyActive = false).
        // Companion fires at fajrTrigger + 45s (abandoned > 30s) within 5min window
        val outcomeCompanion = stateMachine.processAlarmTrigger(
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

        assertTrue(outcomeCompanion is AlarmProcessingOutcome.DeliverShortFallback)
        assertEquals(DeliveryState.SHORT_DELIVERED, store.getConsumedRecord(fajrKey)?.state)

        // Future exact alarm or retry CANNOT replay full adhan
        val outcomeRetry = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger + 60000L,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )
        assertEquals(AlarmProcessingOutcome.AlreadyDelivered, outcomeRetry)
    }

    @Test
    fun testProcessDeathAfterPlayClaimNeverReplaysFullAndYieldsNoShortFallback() {
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

        // Durable claim made before MediaPlayer.start, then process dies
        val claimed = stateMachine.markPlayClaimedBeforeStart(currentToken, fajrKey, fajrTrigger + 100L)
        assertTrue(claimed)
        assertEquals(DeliveryState.PLAY_CLAIMED, store.getConsumedRecord(fajrKey)?.state)

        // Companion fires at fajrTrigger + 45s (abandoned, service dead).
        // Blocker 3: Once PLAY_CLAIMED is recorded, physical playback may have started;
        // it is strictly one-way with NO short fallback and NO full replay.
        val outcomeCompanion = stateMachine.processAlarmTrigger(
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

        assertEquals(AlarmProcessingOutcome.AlreadyDelivered, outcomeCompanion)
        assertEquals(DeliveryState.PLAY_CLAIMED, store.getConsumedRecord(fajrKey)?.state)

        // Retry exact alarm also drops
        val outcomeRetry = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger + 60000L,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )
        assertEquals(AlarmProcessingOutcome.AlreadyDelivered, outcomeRetry)
    }

    @Test
    fun testCrashAfterPhysicalStartWithFailedConsumedWriteYieldsNoShortAndNoFullReplay() {
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

        val playClaimed = stateMachine.markPlayClaimedBeforeStart(currentToken, fajrKey, fajrTrigger + 100L)
        assertTrue(playClaimed)
        assertEquals(DeliveryState.PLAY_CLAIMED, store.getConsumedRecord(fajrKey)?.state)

        // Physical start occurs, but markFullPlaybackStarted storage write fails
        storage.failWrites = true
        val fullStartedPersisted = stateMachine.markFullPlaybackStarted(currentToken, fajrKey, fajrTrigger + 200L)
        assertFalse(fullStartedPersisted)
        // Record remains PLAY_CLAIMED
        assertEquals(DeliveryState.PLAY_CLAIMED, store.getConsumedRecord(fajrKey)?.state)

        // Subsequent companion retry drops without sound
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
        assertEquals(DeliveryState.PLAY_CLAIMED, store.getConsumedRecord(fajrKey)?.state)
    }

    @Test
    fun testLatenessWindowDropsAlarmFiredPastFiveMinutesWithoutSound() {
        val currentToken = store.getGenerationToken()
        val sixMinutesLate = fajrTrigger + (6L * 60L * 1000L)

        val outcome = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = sixMinutesLate,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )

        assertEquals(AlarmProcessingOutcome.ExpiredLate, outcome)
        assertEquals(DeliveryState.EXPIRED_LATE, store.getConsumedRecord(fajrKey)?.state)
    }

    @Test
    fun testEarlyTriggerGuardRejectsEarlyBroadcastsWithoutSoundOrConsumingEvent() {
        val currentToken = store.getGenerationToken()
        // Broadcast triggers 10 seconds before scheduled time (> 5s early threshold)
        val earlyTime = fajrTrigger - 10000L

        val outcome = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = earlyTime,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )

        assertEquals(AlarmProcessingOutcome.TriggerTooEarly, outcome)
        // Event must remain unconsumed
        assertNull(store.getConsumedRecord(fajrKey))
    }

    @Test
    fun testStaleGenerationTokenFromOldPlanIsDropped() {
        // Event triggers with old token 1L when store is at token 2L
        val outcome = stateMachine.processAlarmTrigger(
            intentToken = 1L,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )

        assertEquals(AlarmProcessingOutcome.StaleGenerationToken, outcome)
    }

    // --- Finding 1: Injected Storage Driver Persistence Failures Fail Closed ---

    @Test
    fun testPersistenceFailureAtExactClaimFailsClosedWithNoSound() {
        val currentToken = store.getGenerationToken()
        storage.failWrites = true

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

        assertTrue(outcome is AlarmProcessingOutcome.PersistenceFailure)
        val failure = outcome as AlarmProcessingOutcome.PersistenceFailure
        assertEquals(fajrKey, failure.eventKey)
        assertEquals(DeliveryState.EXACT_CLAIMED, failure.attemptedState)

        // Verify coordinator handling: zero service starts, zero notifications!
        val timeProvider = MutableTimeProvider(fajrTrigger)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        coordinator.handleAlarmTrigger(fajrKey, currentToken, AlarmTriggerType.EXACT)
        assertFalse(serviceGateway.running)
        assertTrue(serviceGateway.startedEvents.isEmpty())
        assertTrue(notifGateway.postedShortAlerts.isEmpty())
    }

    @Test
    fun testPersistenceFailureAtCompanionClaimFailsClosedWithNoSound() {
        val currentToken = store.getGenerationToken()
        storage.failWrites = true

        val outcome = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.COMPANION,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )

        assertTrue(outcome is AlarmProcessingOutcome.PersistenceFailure)
        val failure = outcome as AlarmProcessingOutcome.PersistenceFailure
        assertEquals(fajrKey, failure.eventKey)
        assertEquals(DeliveryState.SHORT_DELIVERED, failure.attemptedState)
    }

    @Test
    fun testPersistenceFailureAtPlayClaimPreventsPhysicalStart() {
        val currentToken = store.getGenerationToken()

        // Exact claim succeeds
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

        // Storage write fails right before MediaPlayer.start
        storage.failWrites = true
        val playClaimed = stateMachine.markPlayClaimedBeforeStart(currentToken, fajrKey, fajrTrigger + 100L)

        // MUST FAIL: service will abort without starting audio
        assertFalse(playClaimed)
    }

    // --- Finding 2: Rigorous Transition Validation & Non-Replay ---

    @Test
    fun testMarkPlayClaimedRequiresMatchingTokenAndExactClaimedState() {
        val currentToken = store.getGenerationToken()

        // 1. Wrong token fails
        assertFalse(stateMachine.markPlayClaimedBeforeStart(99L, fajrKey, fajrTrigger))

        // 2. Unclaimed event fails
        assertFalse(stateMachine.markPlayClaimedBeforeStart(currentToken, fajrKey, fajrTrigger))

        // 3. EXACT_CLAIMED succeeds
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
        assertTrue(stateMachine.markPlayClaimedBeforeStart(currentToken, fajrKey, fajrTrigger + 100L))

        // 4. Repeated call in PLAY_CLAIMED fails
        assertFalse(stateMachine.markPlayClaimedBeforeStart(currentToken, fajrKey, fajrTrigger + 200L))
    }

    @Test
    fun testMarkFullPlaybackStartedRequiresMatchingTokenAndPlayClaimedState() {
        val currentToken = store.getGenerationToken()

        // 1. In EXACT_CLAIMED state (before play claim) fails
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
        assertFalse(stateMachine.markFullPlaybackStarted(currentToken, fajrKey, fajrTrigger + 50L))

        // 2. Play claim made -> now markFullPlaybackStarted succeeds
        assertTrue(stateMachine.markPlayClaimedBeforeStart(currentToken, fajrKey, fajrTrigger + 100L))
        assertTrue(stateMachine.markFullPlaybackStarted(currentToken, fajrKey, fajrTrigger + 200L))

        // 3. Repeated call fails
        assertFalse(stateMachine.markFullPlaybackStarted(currentToken, fajrKey, fajrTrigger + 300L))
    }

    @Test
    fun testStartupFailureNeverRewritesFullConsumedOrDuplicateFallback() {
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
        stateMachine.markPlayClaimedBeforeStart(currentToken, fajrKey, fajrTrigger + 100L)
        stateMachine.markFullPlaybackStarted(currentToken, fajrKey, fajrTrigger + 200L)
        assertEquals(DeliveryState.FULL_CONSUMED, store.getConsumedRecord(fajrKey)?.state)

        // Attempt startup failure after full playback started -> MUST RETURN FALSE and preserve FULL_CONSUMED!
        val fallback = stateMachine.handleServiceStartupFailure(
            expectedToken = currentToken,
            eventKey = fajrKey,
            reason = "test_failure_after_start",
            nowEpochMillis = fajrTrigger + 300L
        )
        assertFalse(fallback)
        assertEquals(DeliveryState.FULL_CONSUMED, store.getConsumedRecord(fajrKey)?.state)
    }

    @Test
    fun testStartupFailureOutsideLatenessWindowTransitionsToSuppressedAndReturnsFalse() {
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

        // Failure occurs 6 minutes after trigger (outside 5min lateness window)
        val fallback = stateMachine.handleServiceStartupFailure(
            expectedToken = currentToken,
            eventKey = fajrKey,
            reason = "too_late",
            nowEpochMillis = fajrTrigger + (6L * 60L * 1000L)
        )
        assertFalse(fallback)
        assertEquals(DeliveryState.SUPPRESSED_OR_FAILED, store.getConsumedRecord(fajrKey)?.state)
    }

    // --- Finding 4: Validate + CAS First Before Cancelling Old Alarms ---

    @Test
    fun testReplacePlanValidateAndCasFirstDoesNotCancelAlarmsOnStaleOrStorageFailure() {
        val timeProvider = MutableTimeProvider(baseTime)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        // Stale token call (expectedToken 99 vs current 2)
        val stalePlanMap = sampleRawPlan(token = 99L)
        val resStale = coordinator.replacePlan(stalePlanMap)
        assertEquals(false, resStale["success"])
        assertEquals("STALE_AUTHORIZATION_TOKEN", resStale["errorCode"])

        // Invariant: active alarms were NOT cancelled!
        assertTrue(scheduler.cancelled.isEmpty())

        // Persistence failure during replacePlan
        storage.failWrites = true
        val validPlanMap = sampleRawPlan(token = 2L)
        val resFailed = coordinator.replacePlan(validPlanMap)
        assertEquals(false, resFailed["success"])
        assertEquals("STORAGE_PERSISTENCE_FAILURE", resFailed["errorCode"])

        // Invariant: active alarms were NOT cancelled!
        assertTrue(scheduler.cancelled.isEmpty())
    }

    // --- Finding 5: Durable Invalidation Before OS Cleanup & Partial Failure Reporting ---

    @Test
    fun testDisableAndResetDurablyInvalidatesFirstAndReportsPartialFailureIfCleanupFails() {
        val timeProvider = MutableTimeProvider(baseTime)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        // Simulate OS cancellation failure
        scheduler.failCancel = true

        val disableRes = coordinator.disableAlarms()
        assertEquals(false, disableRes["success"])
        assertEquals(true, disableRes["authorizationInvalidated"])
        assertEquals(true, disableRes["partialFailure"])
        assertEquals("OS_CLEANUP_INCOMPLETE", disableRes["errorCode"])
        assertEquals(3L, disableRes["token"])

        // Store is nonetheless durably invalidated and disabled!
        assertFalse(store.isEnabled())
        assertEquals(3L, store.getGenerationToken())

        // Re-enable to test resetAll
        store.replacePlan(3L, samplePlan(3L), baseTime)
        assertTrue(store.isEnabled())

        val resetRes = coordinator.resetAll()
        assertEquals(false, resetRes["success"])
        assertEquals(true, resetRes["authorizationInvalidated"])
        assertEquals(true, resetRes["partialFailure"])
        assertEquals("OS_CLEANUP_INCOMPLETE", resetRes["errorCode"])
        assertEquals(5L, resetRes["token"])

        // Store is durably reset!
        assertFalse(store.isEnabled())
        assertEquals(5L, store.getGenerationToken())
        assertTrue(store.getConsumedLedgerSnapshot().isEmpty())
    }

    // --- Finding 6: Suppression via Channels and DND/Silent ---

    @Test
    fun testStatusChannelBlockedSuppressesFullAdhan() {
        val currentToken = store.getGenerationToken()

        val outcome = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = true, // Status channel disabled by user!
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )

        // Must NOT launch full adhan; falls back to short notification
        assertTrue(outcome is AlarmProcessingOutcome.DeliverShortFallback)
        assertEquals(DeliveryState.SHORT_DELIVERED, store.getConsumedRecord(fajrKey)?.state)
    }

    @Test
    fun testDndOrSilentSuppressesFullAdhan() {
        val currentToken = store.getGenerationToken()

        val outcome = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = true, // DND or Silent active!
            isServiceCurrentlyActive = false
        )

        // Must NOT launch full adhan; falls back to short notification
        assertTrue(outcome is AlarmProcessingOutcome.DeliverShortFallback)
        assertEquals(DeliveryState.SHORT_DELIVERED, store.getConsumedRecord(fajrKey)?.state)
    }

    @Test
    fun testVoiceChannelBlockedSuppressesShortAlert() {
        val timeProvider = MutableTimeProvider(fajrTrigger)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        // Block malmo_fajr channel
        notifGateway.blockedVoiceChannels.add("malmo_fajr")

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        // Denied exact -> falls back to companion short alert
        scheduler.canScheduleExact = false
        coordinator.handleAlarmTrigger(fajrKey, store.getGenerationToken(), AlarmTriggerType.COMPANION)

        // Since malmo_fajr channel is blocked, notification must NOT be posted!
        assertTrue(notifGateway.postedShortAlerts.isEmpty())
    }

    // --- Finding 7: 45s Companion Offset When Exact Allowed vs Event Instant When Denied ---

    @Test
    fun testReplacePlanOffsetsCompanionBy45SecondsWhenExactAllowed() {
        val timeProvider = MutableTimeProvider(baseTime)
        val scheduler = FakeAlarmScheduler()
        scheduler.canScheduleExact = true
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        coordinator.replacePlan(sampleRawPlan(store.getGenerationToken()))

        assertEquals(fajrTrigger, scheduler.scheduledExactTimes[fajrKey])
        assertEquals(fajrTrigger + 45000L, scheduler.scheduledCompanionTimes[fajrKey])
    }

    @Test
    fun testReplacePlanSchedulesCompanionAtEventInstantWhenExactDenied() {
        val timeProvider = MutableTimeProvider(baseTime)
        val scheduler = FakeAlarmScheduler()
        scheduler.canScheduleExact = false // Denied exact alarm permission
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        coordinator.replacePlan(sampleRawPlan(store.getGenerationToken()))

        // Companion scheduled directly at event instant
        assertEquals(fajrTrigger, scheduler.scheduledCompanionTimes[fajrKey])
        assertNull(scheduler.scheduledExactTimes[fajrKey])
    }

    // --- Finding 8: Confirmed Synchronous Stop ---

    @Test
    fun testConfirmedSynchronousStopStopsRunningServiceWithoutSleep() {
        val timeProvider = MutableTimeProvider(baseTime)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()
        serviceGateway.running = true

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        val stopped = coordinator.stopActiveAdhanPlayback()
        assertTrue(stopped)
        assertFalse(serviceGateway.running)
    }

    @Test
    fun testBootRestoreSchedulesFutureUnconsumedEventsOnly() {
        val timeProvider = MutableTimeProvider(fajrTrigger - 10000L)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        coordinator.restoreScheduleOnBootOrTimeChange()

        // Future event scheduled
        assertTrue(scheduler.scheduledExact.contains(fajrKey))
        assertTrue(scheduler.scheduledCompanion.contains(fajrKey))
        // Zero audio played or services started on boot
        assertFalse(serviceGateway.running)
        assertTrue(notifGateway.postedShortAlerts.isEmpty())
    }

    // --- Finding 7: Scheduler Gateway Failures & Zero Future Events ---

    @Test
    fun testReplacePlanSchedulerGatewayFailureSurfacesIncompleteAndSuccessFalse() {
        val timeProvider = MutableTimeProvider(baseTime)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        // 1. Exact schedule failure
        scheduler.failExact = true
        val resExactFail = coordinator.replacePlan(sampleRawPlan(store.getGenerationToken()))
        assertEquals(false, resExactFail["success"])
        assertEquals(true, resExactFail["authorizationInvalidated"])
        assertEquals(true, resExactFail["partialFailure"])
        assertEquals("ALARM_SCHEDULING_INCOMPLETE", resExactFail["errorCode"])
        assertEquals(false, resExactFail["exactAlarmsUsed"])
        assertEquals(true, resExactFail["companionAlarmsUsed"])
        assertEquals(0, resExactFail["exactScheduledCount"])
        assertEquals(1, resExactFail["companionScheduledCount"])

        // Reset scheduler flags and get fresh token
        scheduler.failExact = false
        val tokenAfterExactFail = store.getGenerationToken()

        // 2. Companion schedule failure
        scheduler.failCompanion = true
        val resCompFail = coordinator.replacePlan(sampleRawPlan(tokenAfterExactFail))
        assertEquals(false, resCompFail["success"])
        assertEquals(true, resCompFail["authorizationInvalidated"])
        assertEquals(true, resCompFail["partialFailure"])
        assertEquals("ALARM_SCHEDULING_INCOMPLETE", resCompFail["errorCode"])
        assertEquals(true, resCompFail["exactAlarmsUsed"])
        assertEquals(false, resCompFail["companionAlarmsUsed"])
        assertEquals(1, resCompFail["exactScheduledCount"])
        assertEquals(0, resCompFail["companionScheduledCount"])

        // 3. Old alarm cancellation failure during replacePlan
        scheduler.failCompanion = false
        scheduler.failCancel = true
        val tokenAfterCompFail = store.getGenerationToken()
        val resCancelFail = coordinator.replacePlan(sampleRawPlan(tokenAfterCompFail))
        assertEquals(false, resCancelFail["success"])
        assertEquals(true, resCancelFail["authorizationInvalidated"])
        assertEquals(true, resCancelFail["partialFailure"])
        assertEquals("OS_CLEANUP_INCOMPLETE", resCancelFail["errorCode"])
    }

    @Test
    fun testReplacePlanWithZeroFutureEventsSucceedsWithZeroScheduled() {
        val timeProvider = MutableTimeProvider(baseTime)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        val emptyPlanMap = mapOf(
            "expectedToken" to store.getGenerationToken(),
            "cityId" to 360630,
            "cityNameAr" to "القاهرة",
            "timezone" to "Africa/Cairo",
            "generalVoiceId" to "adam",
            "fajrVoiceId" to "malmo_fajr",
            "mode" to "full_adhan",
            "coverageHorizonUtc" to baseTime + 864000000L,
            "events" to emptyList<Map<String, Any>>()
        )

        val res = coordinator.replacePlan(emptyPlanMap)
        assertEquals(true, res["success"])
        assertEquals(true, res["authorizationInvalidated"])
        assertEquals(0, res["scheduledCount"])
        assertEquals(0, res["attemptedCount"])
        assertEquals(false, res["exactAlarmsUsed"])
        assertEquals(false, res["companionAlarmsUsed"])
        assertNull(res["partialFailure"])
    }

    // --- Finding 2: Synchronized Pre-Start Protocol ---

    @Test
    fun testAuthorizeAndStartPlaybackUnderLockBlocksStaleSoundAfterResetOrDisable() {
        val timeProvider = MutableTimeProvider(fajrTrigger)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        val currentToken = store.getGenerationToken()

        // 1. Legitimate playback: active plan, matching token, not suppressed
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

        var physicalStarted = false
        val authorized = coordinator.authorizeAndStartPlayback(
            token = currentToken,
            eventKey = fajrKey,
            nowEpochMillis = fajrTrigger + 100L,
            isSuppressed = { false },
            onPhysicalStart = {
                physicalStarted = true
                true
            }
        )

        assertTrue(authorized.isFullyDurable)
        assertTrue(physicalStarted)
        assertEquals(DeliveryState.FULL_CONSUMED, store.getConsumedRecord(fajrKey)?.state)

        // 2. Disable store -> attempt start with old token or after disable MUST be rejected without sound
        coordinator.disableAlarms()

        var staleStarted = false
        val rejectedAfterDisable = coordinator.authorizeAndStartPlayback(
            token = currentToken,
            eventKey = fajrKey,
            nowEpochMillis = fajrTrigger + 200L,
            isSuppressed = { false },
            onPhysicalStart = {
                staleStarted = true
                true
            }
        )

        assertFalse(rejectedAfterDisable.isFullyDurable)
        assertFalse(staleStarted)

        // 3. Suppression check: re-enable store, claim exact, but suppressed immediately before play
        store.reset()
        store.replacePlan(store.getGenerationToken(), samplePlan(store.getGenerationToken()), fajrTrigger)
        val freshToken = store.getGenerationToken()

        stateMachine.processAlarmTrigger(
            intentToken = freshToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.EXACT,
            nowEpochMillis = fajrTrigger,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )

        var suppressedStarted = false
        val rejectedSuppressed = coordinator.authorizeAndStartPlayback(
            token = freshToken,
            eventKey = fajrKey,
            nowEpochMillis = fajrTrigger + 100L,
            isSuppressed = { true },
            onPhysicalStart = {
                suppressedStarted = true
                true
            }
        )

        assertFalse(rejectedSuppressed.isFullyDurable)
        assertFalse(suppressedStarted)
    }

    // --- Finding 1 & 2 (Manual Playback Lease & Synchronized Pre-Start Failure Protocol) ---

    @Test
    fun testManualPlaybackLeaseSingleFunctionApiAndLifecycle() {
        val timeProvider = MutableTimeProvider(baseTime)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        // 1. Initial state: lease is inactive
        assertFalse(coordinator.isManualPlaybackLeaseActive())
        assertNull(coordinator.getManualPlaybackLease())

        // 2. Invalid requestId rejected
        val resNull = coordinator.acquireManualPlaybackLease(null, "session-1")
        assertEquals(false, resNull["acquired"])
        assertEquals("INVALID_REQUEST_ID", resNull["errorCode"])

        val resBlank = coordinator.acquireManualPlaybackLease("   ", "session-1")
        assertEquals(false, resBlank["acquired"])
        assertEquals("INVALID_REQUEST_ID", resBlank["errorCode"])

        val resLong = coordinator.acquireManualPlaybackLease("a".repeat(257), "session-1")
        assertEquals(false, resLong["acquired"])
        assertEquals("INVALID_REQUEST_ID", resLong["errorCode"])

        // 3. Acquire valid lease
        val resAcquire = coordinator.acquireManualPlaybackLease("req-1", "session-1")
        assertEquals(true, resAcquire["acquired"])
        val token1 = resAcquire["leaseToken"] as String
        assertNotNull(token1)
        assertTrue(coordinator.isManualPlaybackLeaseActive())
        assertEquals("req-1", coordinator.getManualPlaybackLease()?.requestId)

        // 4. Idempotent retry with same session and requestId
        val resIdempotent = coordinator.acquireManualPlaybackLease("req-1", "session-1")
        assertEquals(true, resIdempotent["acquired"])
        assertEquals(true, resIdempotent["idempotent"])
        assertEquals(token1, resIdempotent["leaseToken"])

        // 5. Competing request rejected as LEASE_BUSY
        val resBusy = coordinator.acquireManualPlaybackLease("req-2", "session-1")
        assertEquals(false, resBusy["acquired"])
        assertEquals("LEASE_BUSY", resBusy["errorCode"])

        val resBusyDiffSession = coordinator.acquireManualPlaybackLease("req-1", "session-2")
        assertEquals(false, resBusyDiffSession["acquired"])
        assertEquals("LEASE_BUSY", resBusyDiffSession["errorCode"])

        // 6. Release with mismatched token fails to clear lease
        val resMismatched = coordinator.releaseManualPlaybackLease("wrong-token")
        assertEquals(true, resMismatched["released"])
        assertEquals(false, resMismatched["cleared"])
        assertEquals("token_mismatch", resMismatched["reason"])
        assertTrue(coordinator.isManualPlaybackLeaseActive())

        // 7. Release with correct token clears lease
        val resRelease = coordinator.releaseManualPlaybackLease(token1)
        assertEquals(true, resRelease["released"])
        assertEquals(true, resRelease["cleared"])
        assertFalse(coordinator.isManualPlaybackLeaseActive())
        assertNull(coordinator.getManualPlaybackLease())

        // 8. Subsequent release reports no active lease
        val resNoLease = coordinator.releaseManualPlaybackLease(token1)
        assertEquals(true, resNoLease["released"])
        assertEquals(false, resNoLease["cleared"])
        assertEquals("no_active_lease", resNoLease["reason"])
    }

    @Test
    fun testAcquireManualPlaybackLeaseStopsActiveAdhanService() {
        val timeProvider = MutableTimeProvider(baseTime)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()
        serviceGateway.running = true

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        val res = coordinator.acquireManualPlaybackLease("req-stop-test", "session-1")
        assertEquals(true, res["acquired"])
        assertTrue(coordinator.isManualPlaybackLeaseActive())
        // Active service was stopped
        assertFalse(serviceGateway.running)
    }

    @Test
    fun testAcquireManualPlaybackLeaseFailsIfActiveServiceStopFails() {
        val timeProvider = MutableTimeProvider(baseTime)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()
        serviceGateway.running = true
        serviceGateway.failStop = true

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        val res = coordinator.acquireManualPlaybackLease("req-stop-fail", "session-1")
        assertEquals(false, res["acquired"])
        assertEquals("NATIVE_SERVICE_STOP_FAILED", res["errorCode"])
        assertFalse(coordinator.isManualPlaybackLeaseActive())
    }

    @Test
    fun testPrestartFailureOrder1LeaseAcquiredBeforePrestartFailureYieldsSilentAlertOnly() {
        val timeProvider = MutableTimeProvider(fajrTrigger)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        val currentToken = store.getGenerationToken()

        // 1. Alarm triggers and claims EXACT_CLAIMED
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
        assertEquals(DeliveryState.EXACT_CLAIMED, store.getConsumedRecord(fajrKey)?.state)

        // 2. While service prepares, manual playback lease is acquired
        val leaseRes = coordinator.acquireManualPlaybackLease("quran-recitation", "session-1")
        assertEquals(true, leaseRes["acquired"])
        assertTrue(coordinator.isManualPlaybackLeaseActive())

        // 3. Service encounters prestart failure (e.g. audio_focus_denied)
        val handled = coordinator.handleServicePrestartFailure(
            token = currentToken,
            eventKey = fajrKey,
            reason = "audio_focus_denied",
            nowEpochMillis = fajrTrigger + 1000L
        )

        // INVARIANTS:
        assertTrue("Prestart failure under lease must be handled as manual suppression", handled)
        assertEquals(DeliveryState.MANUAL_SUPPRESSED, store.getConsumedRecord(fajrKey)?.state)
        assertEquals(listOf(fajrKey), notifGateway.postedSilentManualAlerts)
        assertTrue("Must NOT emit audible short alert when lease is active", notifGateway.postedShortAlerts.isEmpty())
    }

    @Test
    fun testPrestartFailureOrder2PrestartFailureBeforeLeaseYieldsShortAlertAndSubsequentLeaseSucceeds() {
        val timeProvider = MutableTimeProvider(fajrTrigger)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        val currentToken = store.getGenerationToken()

        // 1. Alarm triggers and claims EXACT_CLAIMED
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

        // 2. Prestart failure occurs BEFORE manual lease is acquired
        assertFalse(coordinator.isManualPlaybackLeaseActive())
        val handled = coordinator.handleServicePrestartFailure(
            token = currentToken,
            eventKey = fajrKey,
            reason = "start_foreground_failed",
            nowEpochMillis = fajrTrigger + 1000L
        )

        // INVARIANTS:
        assertTrue(handled)
        assertEquals(DeliveryState.SHORT_DELIVERED, store.getConsumedRecord(fajrKey)?.state)
        assertEquals(listOf(fajrKey), notifGateway.postedShortAlerts)
        assertTrue("Silent manual alert must NOT be posted when no lease was active", notifGateway.postedSilentManualAlerts.isEmpty())

        // 3. Subsequently, user starts manual playback: lease acquisition succeeds cleanly
        val leaseRes = coordinator.acquireManualPlaybackLease("quran-recitation", "session-1")
        assertEquals(true, leaseRes["acquired"])
        assertTrue(coordinator.isManualPlaybackLeaseActive())
        assertTrue("Previous owned short fallback notification must be cancelled upon manual lease grant", notifGateway.cancelledNotifications.contains(fajrKey))

        // 4. Repeated trigger / retry for same event drops with zero duplicate alert
        val retryOutcome = stateMachine.processAlarmTrigger(
            intentToken = currentToken,
            eventKey = fajrKey,
            alarmType = AlarmTriggerType.COMPANION,
            nowEpochMillis = fajrTrigger + 10000L,
            canScheduleExactAlarms = true,
            notificationsAllowed = true,
            statusChannelBlocked = false,
            dndOrSilentSuppresses = false,
            isServiceCurrentlyActive = false
        )
        assertEquals(AlarmProcessingOutcome.AlreadyDelivered, retryOutcome)
        assertEquals(1, notifGateway.postedShortAlerts.size)
        assertEquals(0, notifGateway.postedSilentManualAlerts.size)
    }

    @Test
    fun testHandleServicePrestartFailureAllDistinctFailureReasons() {
        val distinctReasons = listOf(
            "start_foreground_failed",
            "suppressed_by_silent_dnd_or_status_channel",
            "audio_focus_denied",
            "media_player_prepare_failed",
            "service_launch_failed"
        )

        for (reason in distinctReasons) {
            val timeProvider = MutableTimeProvider(fajrTrigger)
            val scheduler = FakeAlarmScheduler()
            val notifGateway = FakeNotificationGateway()
            val serviceGateway = FakeServiceGateway()

            // Fresh store and state machine for each reason iteration
            val localStore = PrayerAlarmStore(InMemoryStorageDriver())
            localStore.replacePlan(1L, samplePlan(1L), baseTime)
            val localCoordinator = PrayerAlarmCoordinator(
                store = localStore,
                timeProvider = timeProvider,
                alarmScheduler = scheduler,
                notificationGateway = notifGateway,
                serviceGateway = serviceGateway
            )

            val token = localStore.getGenerationToken()

            // Claim exact
            localCoordinator.stateMachine.processAlarmTrigger(
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
            assertEquals(DeliveryState.EXACT_CLAIMED, localStore.getConsumedRecord(fajrKey)?.state)

            val result = localCoordinator.handleServicePrestartFailure(
                token = token,
                eventKey = fajrKey,
                reason = reason,
                nowEpochMillis = fajrTrigger + 500L
            )

            assertTrue("Reason '$reason' must be successfully handled", result)
            assertEquals(DeliveryState.SHORT_DELIVERED, localStore.getConsumedRecord(fajrKey)?.state)
            assertEquals(listOf(fajrKey), notifGateway.postedShortAlerts)
            assertTrue(notifGateway.postedSilentManualAlerts.isEmpty())
        }
    }

    @Test
    fun testHandleServicePrestartFailurePersistenceFailureFailsClosedWithZeroNotifications() {
        val timeProvider = MutableTimeProvider(fajrTrigger)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        val currentToken = store.getGenerationToken()

        // Claim exact
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

        // Storage write fails
        storage.failWrites = true

        val handled = coordinator.handleServicePrestartFailure(
            token = currentToken,
            eventKey = fajrKey,
            reason = "audio_focus_denied",
            nowEpochMillis = fajrTrigger + 1000L
        )

        assertFalse("Must fail closed on persistence failure", handled)
        assertTrue("Zero audible alerts on storage failure", notifGateway.postedShortAlerts.isEmpty())
        assertTrue("Zero silent alerts on storage failure", notifGateway.postedSilentManualAlerts.isEmpty())
    }

    @Test
    fun testHandleServicePrestartFailureTerminalStateImmutability() {
        val timeProvider = MutableTimeProvider(fajrTrigger)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

        val currentToken = store.getGenerationToken()

        // 1. Advance to PLAY_CLAIMED
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
        stateMachine.markPlayClaimedBeforeStart(currentToken, fajrKey, fajrTrigger + 100L)
        assertEquals(DeliveryState.PLAY_CLAIMED, store.getConsumedRecord(fajrKey)?.state)

        // Prestart failure attempted in PLAY_CLAIMED -> must be rejected without notification
        val handledInPlayClaimed = coordinator.handleServicePrestartFailure(
            token = currentToken,
            eventKey = fajrKey,
            reason = "media_player_prepare_failed",
            nowEpochMillis = fajrTrigger + 200L
        )
        assertFalse(handledInPlayClaimed)
        assertEquals(DeliveryState.PLAY_CLAIMED, store.getConsumedRecord(fajrKey)?.state)
        assertTrue(notifGateway.postedShortAlerts.isEmpty())

        // 2. Advance to FULL_CONSUMED
        stateMachine.markFullPlaybackStarted(currentToken, fajrKey, fajrTrigger + 300L)
        assertEquals(DeliveryState.FULL_CONSUMED, store.getConsumedRecord(fajrKey)?.state)

        val handledInFullConsumed = coordinator.handleServicePrestartFailure(
            token = currentToken,
            eventKey = fajrKey,
            reason = "audio_focus_denied",
            nowEpochMillis = fajrTrigger + 400L
        )
        assertFalse(handledInFullConsumed)
        assertEquals(DeliveryState.FULL_CONSUMED, store.getConsumedRecord(fajrKey)?.state)
        assertTrue(notifGateway.postedShortAlerts.isEmpty())
    }

    @Test
    fun testHandleServicePrestartFailureVoiceChannelBlockedSuppressesShortAlert() {
        val timeProvider = MutableTimeProvider(fajrTrigger)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        // Block malmo_fajr voice channel
        notifGateway.blockedVoiceChannels.add("malmo_fajr")

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

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

        val handled = coordinator.handleServicePrestartFailure(
            token = currentToken,
            eventKey = fajrKey,
            reason = "media_player_prepare_failed",
            nowEpochMillis = fajrTrigger + 1000L
        )

        // Fallback recorded in ledger, but notification suppressed because channel blocked
        assertTrue(handled)
        assertEquals(DeliveryState.SHORT_DELIVERED, store.getConsumedRecord(fajrKey)?.state)
        assertTrue("Notification must be suppressed when voice channel is blocked", notifGateway.postedShortAlerts.isEmpty())
    }

    @Test
    fun testHandleServicePrestartFailureOutsideLatenessWindowDropsWithoutSound() {
        val timeProvider = MutableTimeProvider(fajrTrigger)
        val scheduler = FakeAlarmScheduler()
        val notifGateway = FakeNotificationGateway()
        val serviceGateway = FakeServiceGateway()

        val coordinator = PrayerAlarmCoordinator(
            store = store,
            timeProvider = timeProvider,
            alarmScheduler = scheduler,
            notificationGateway = notifGateway,
            serviceGateway = serviceGateway
        )

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

        // Prestart failure occurs 6 minutes late (> 5min lateness window)
        val lateTime = fajrTrigger + (6L * 60L * 1000L)
        val handled = coordinator.handleServicePrestartFailure(
            token = currentToken,
            eventKey = fajrKey,
            reason = "media_player_prepare_failed",
            nowEpochMillis = lateTime
        )

        assertFalse("Must return false when outside lateness window", handled)
        assertEquals(DeliveryState.SUPPRESSED_OR_FAILED, store.getConsumedRecord(fajrKey)?.state)
        assertTrue("Must NOT post short alert when outside lateness window", notifGateway.postedShortAlerts.isEmpty())
    }
}
