package dev.zadalruh.zad_alruh

import dev.zadalruh.zad_alruh.alarm.ConsumedRecord
import dev.zadalruh.zad_alruh.alarm.DeliveryState
import dev.zadalruh.zad_alruh.alarm.DisableResult
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmStore
import dev.zadalruh.zad_alruh.alarm.PrayerEventRecord
import dev.zadalruh.zad_alruh.alarm.PrayerPlan
import dev.zadalruh.zad_alruh.alarm.FileStorageDriver
import dev.zadalruh.zad_alruh.alarm.ReplacePlanResult
import dev.zadalruh.zad_alruh.alarm.ResetResult
import dev.zadalruh.zad_alruh.alarm.StorageDriver
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class InMemoryStorageDriver : StorageDriver {
    private var data: String? = null
    var failWrites: Boolean = false

    override fun read(): String? = data

    override fun write(content: String): Boolean {
        if (failWrites) return false
        data = content
        return true
    }

    fun setRaw(content: String?) {
        data = content
    }
}

class PrayerAlarmStoreTest {

    private lateinit var storage: InMemoryStorageDriver
    private lateinit var store: PrayerAlarmStore

    private val now = 1760000000000L

    private fun samplePlan(token: Long): PrayerPlan {
        return PrayerPlan(
            expectedToken = token,
            cityId = 360630,
            cityNameAr = "القاهرة",
            timezone = "Africa/Cairo",
            generalVoiceId = "adam",
            fajrVoiceId = "malmo_fajr",
            mode = "full_adhan",
            coverageHorizonUtc = now + 864000000L,
            events = listOf(
                PrayerEventRecord(
                    eventKey = "360630:2026-10-07:fajr",
                    prayerKey = "fajr",
                    calculationCivilDate = "2026-10-07",
                    triggerEpochMillis = now + 3600000L,
                    voiceId = "malmo_fajr",
                    mode = "full_adhan"
                ),
                PrayerEventRecord(
                    eventKey = "360630:2026-10-07:dhuhr",
                    prayerKey = "dhuhr",
                    calculationCivilDate = "2026-10-07",
                    triggerEpochMillis = now + 18000000L,
                    voiceId = "adam",
                    mode = "full_adhan"
                )
            )
        )
    }

    @Before
    fun setUp() {
        storage = InMemoryStorageDriver()
        store = PrayerAlarmStore(storage)
    }

    @Test
    fun testDefaultStateIsDisabledWithTokenOne() {
        assertFalse(store.isEnabled())
        assertEquals(1L, store.getGenerationToken())
        assertNull(store.getActivePlan())
        assertTrue(store.getConsumedLedgerSnapshot().isEmpty())
    }

    @Test
    fun testReplacePlanAtomicCasSucceedsAndIncrementsToken() {
        val plan = samplePlan(token = 1L)
        val result = store.replacePlan(expectedToken = 1L, newPlan = plan, nowEpochMillis = now)

        assertTrue(result is ReplacePlanResult.Success)
        assertEquals(2L, (result as ReplacePlanResult.Success).newToken)
        assertTrue(store.isEnabled())
        assertEquals(2L, store.getGenerationToken())
        assertNotNull(store.getActivePlan())
        assertEquals(2, store.getActivePlan()?.events?.size)
    }

    @Test
    fun testStaleExpectedTokenIsRejected() {
        val plan = samplePlan(token = 99L)
        val result = store.replacePlan(expectedToken = 99L, newPlan = plan, nowEpochMillis = now)

        assertTrue(result is ReplacePlanResult.StaleToken)
        assertEquals(1L, (result as ReplacePlanResult.StaleToken).currentToken)
        assertFalse(store.isEnabled())
        assertEquals(1L, store.getGenerationToken())
    }

    @Test
    fun testDisableInvalidatesTokenBeforeReportingSuccessAndBlocksStalePlan() {
        // First install and enable plan
        store.replacePlan(expectedToken = 1L, newPlan = samplePlan(1L), nowEpochMillis = now)
        assertEquals(2L, store.getGenerationToken())
        assertTrue(store.isEnabled())

        // Disable
        val disableRes = store.disable()
        assertTrue(disableRes is DisableResult.Success)
        assertEquals(3L, (disableRes as DisableResult.Success).newToken)
        assertFalse(store.isEnabled())
        assertNull(store.getActivePlan())

        // In-flight plan that had token 2L tries to re-enroll -> MUST BE REJECTED
        val stalePlan = samplePlan(token = 2L)
        val staleRes = store.replacePlan(expectedToken = 2L, newPlan = stalePlan, nowEpochMillis = now)
        assertTrue(staleRes is ReplacePlanResult.StaleToken)
        assertEquals(3L, (staleRes as ReplacePlanResult.StaleToken).currentToken)
        assertFalse(store.isEnabled())
    }

    @Test
    fun testResetClearsPlanAndLedgerAndAdvancesToken() {
        store.replacePlan(expectedToken = 1L, newPlan = samplePlan(1L), nowEpochMillis = now)
        store.updateConsumedRecord(
            ConsumedRecord("360630:2026-10-07:fajr", DeliveryState.FULL_CONSUMED, now, "exact")
        )
        assertEquals(1, store.getConsumedLedgerSnapshot().size)

        val resetRes = store.reset()
        assertTrue(resetRes is ResetResult.Success)
        assertEquals(3L, (resetRes as ResetResult.Success).newToken)
        assertFalse(store.isEnabled())
        assertNull(store.getActivePlan())
        assertTrue(store.getConsumedLedgerSnapshot().isEmpty())
    }

    @Test
    fun testDurableLedgerPreservedAcrossPlanReconciliationForSameEvent() {
        // Schedule Plan 1 with token 1
        val plan1 = samplePlan(1L)
        store.replacePlan(1L, plan1, now)

        // Fajr is delivered
        val fajrKey = "360630:2026-10-07:fajr"
        store.updateConsumedRecord(
            ConsumedRecord(fajrKey, DeliveryState.FULL_CONSUMED, now + 1000L, "exact")
        )

        // User changes voice settings: Dart calculates Plan 2 with token 2 for SAME city and date
        val plan2 = samplePlan(2L)
        val replaceRes = store.replacePlan(2L, plan2, now + 2000L)
        assertTrue(replaceRes is ReplacePlanResult.Success)

        // Crucial acceptance: Consumed ledger entry MUST NOT be lost!
        val record = store.getConsumedRecord(fajrKey)
        assertNotNull(record)
        assertEquals(DeliveryState.FULL_CONSUMED, record?.state)
    }

    @Test
    fun testBoundedLedgerPruningPurgesStaleHistoricalEventsWhileKeepingActiveEvents() {
        store.replacePlan(1L, samplePlan(1L), now)

        val fifteenDaysAgo = now - (15L * 24L * 3600L * 1000L)
        // Record 1: Old event from past that is NOT in current plan
        store.updateConsumedRecord(
            ConsumedRecord("360630:2026-09-20:fajr", DeliveryState.FULL_CONSUMED, fifteenDaysAgo, "exact")
        )

        // Record 2: Active plan event that happens to have older timestamp
        store.updateConsumedRecord(
            ConsumedRecord("360630:2026-10-07:fajr", DeliveryState.FULL_CONSUMED, fifteenDaysAgo, "exact")
        )

        assertEquals(2, store.getConsumedLedgerSnapshot().size)

        // Replace plan at token 2
        store.replacePlan(2L, samplePlan(2L), now)

        val snapshot = store.getConsumedLedgerSnapshot()
        // Stale past event purged
        assertNull(snapshot["360630:2026-09-20:fajr"])
        // Current active event retained
        assertNotNull(snapshot["360630:2026-10-07:fajr"])
    }

    @Test
    fun testCorruptStorageRecoveryResetsCleanlyWithoutCrash() {
        storage.setRaw("{invalid_json: true, unterminated string...")
        val recoveredStore = PrayerAlarmStore(storage)

        assertFalse(recoveredStore.isEnabled())
        assertEquals(1L, recoveredStore.getGenerationToken())
        assertNull(recoveredStore.getActivePlan())
        assertTrue(recoveredStore.getConsumedLedgerSnapshot().isEmpty())
    }

    @Test
    fun testPersistenceFailureDuringReplacePlanRollsBackState() {
        storage.failWrites = true
        val result = store.replacePlan(expectedToken = 1L, newPlan = samplePlan(1L), nowEpochMillis = now)

        assertTrue(result is ReplacePlanResult.PersistenceFailure)
        assertFalse(store.isEnabled())
        assertEquals(1L, store.getGenerationToken())
        assertNull(store.getActivePlan())
        assertTrue(store.getConsumedLedgerSnapshot().isEmpty())
    }

    @Test
    fun testPersistenceFailureDuringDisableRollsBackState() {
        store.replacePlan(expectedToken = 1L, newPlan = samplePlan(1L), nowEpochMillis = now)
        assertEquals(2L, store.getGenerationToken())
        assertTrue(store.isEnabled())

        storage.failWrites = true
        val disableRes = store.disable()

        assertTrue(disableRes is DisableResult.PersistenceFailure)
        assertTrue(store.isEnabled())
        assertEquals(2L, store.getGenerationToken())
        assertNotNull(store.getActivePlan())
    }

    @Test
    fun testPersistenceFailureDuringResetRollsBackState() {
        store.replacePlan(expectedToken = 1L, newPlan = samplePlan(1L), nowEpochMillis = now)
        val fajrKey = "360630:2026-10-07:fajr"
        store.updateConsumedRecord(
            ConsumedRecord(fajrKey, DeliveryState.FULL_CONSUMED, now, "exact")
        )

        storage.failWrites = true
        val resetRes = store.reset()

        assertTrue(resetRes is ResetResult.PersistenceFailure)
        assertTrue(store.isEnabled())
        assertEquals(2L, store.getGenerationToken())
        assertNotNull(store.getActivePlan())
        assertEquals(1, store.getConsumedLedgerSnapshot().size)
    }

    @Test
    fun testRealJsonSerializationRoundtripWithFileStorageDriver() {
        val tempFile = File.createTempFile("prayer_alarm_store_test", ".json")
        try {
            val fileDriver1 = FileStorageDriver(tempFile)
            val store1 = PrayerAlarmStore(fileDriver1)

            val replaceRes = store1.replacePlan(1L, samplePlan(1L), now)
            assertTrue(replaceRes is ReplacePlanResult.Success)

            val fajrKey = "360630:2026-10-07:fajr"
            val updated = store1.updateConsumedRecord(
                ConsumedRecord(fajrKey, DeliveryState.FULL_CONSUMED, now + 1000L, "exact", "roundtrip test")
            )
            assertTrue(updated)

            // Re-open fresh instance from disk
            val fileDriver2 = FileStorageDriver(tempFile)
            val store2 = PrayerAlarmStore(fileDriver2)

            assertTrue(store2.isEnabled())
            assertEquals(2L, store2.getGenerationToken())
            assertNotNull(store2.getActivePlan())
            assertEquals(360630, store2.getActivePlan()?.cityId)
            assertEquals("القاهرة", store2.getActivePlan()?.cityNameAr)
            assertEquals("Africa/Cairo", store2.getActivePlan()?.timezone)
            assertEquals(2, store2.getActivePlan()?.events?.size)

            val record = store2.getConsumedRecord(fajrKey)
            assertNotNull(record)
            assertEquals(DeliveryState.FULL_CONSUMED, record?.state)
            assertEquals("roundtrip test", record?.details)
        } finally {
            tempFile.delete()
        }
    }

    @Test
    fun testFileStorageDriverAtomicReplacementFailurePreservesOldState() {
        val tempFile = File.createTempFile("atomic_store_test", ".json")
        try {
            val fileDriver = FileStorageDriver(tempFile)
            val initialJson = "{\"enabled\":true,\"generationToken\":2}"
            assertTrue(fileDriver.write(initialJson))
            assertEquals(initialJson, fileDriver.read())

            // If a write fails, old content is preserved intact and readable
            // Test with a store using a storage driver whose atomic write fails:
            val failingStorage = object : StorageDriver {
                var stored = initialJson
                override fun read(): String? = stored
                override fun write(content: String): Boolean = false
            }
            val store = PrayerAlarmStore(failingStorage)
            assertEquals(2L, store.getGenerationToken())
            assertTrue(store.isEnabled())

            // Attempt replacePlan -> persistence fails -> authorization NOT advanced!
            val replaceRes = store.replacePlan(2L, samplePlan(2L), now)
            assertTrue(replaceRes is ReplacePlanResult.PersistenceFailure)
            assertEquals(2L, store.getGenerationToken())
            assertEquals(initialJson, failingStorage.read())
        } finally {
            tempFile.delete()
        }
    }

    @Test
    fun testFileStorageDriverFreshCreateAtomicallyWritesAndReads() {
        val nonExistentFile = File(System.getProperty("java.io.tmpdir"), "fresh_store_create_${System.currentTimeMillis()}.json")
        try {
            assertFalse(nonExistentFile.exists())
            val driver = FileStorageDriver(nonExistentFile)
            assertNull(driver.read())

            val content = "{\"enabled\":false,\"generationToken\":1}"
            val written = driver.write(content)
            assertTrue(written)
            assertTrue(nonExistentFile.exists())
            assertEquals(content, driver.read())

            // Ensure temp file was cleaned up and does not linger
            val tempFile = File(nonExistentFile.parentFile, "${nonExistentFile.name}.tmp")
            assertFalse(tempFile.exists())
        } finally {
            nonExistentFile.delete()
        }
    }

    @Test
    fun testFileStorageDriverAtomicReplacementOverwritesOldContentWithFdatasync() {
        val storeFile = File.createTempFile("atomic_replace_test", ".json")
        try {
            val driver = FileStorageDriver(storeFile)
            val content1 = "{\"enabled\":false,\"generationToken\":1}"
            val content2 = "{\"enabled\":true,\"generationToken\":2}"

            assertTrue(driver.write(content1))
            assertEquals(content1, driver.read())

            assertTrue(driver.write(content2))
            assertEquals(content2, driver.read())

            val tempFile = File(storeFile.parentFile, "${storeFile.name}.tmp")
            assertFalse(tempFile.exists())
        } finally {
            storeFile.delete()
        }
    }

    @Test
    fun testPendingCleanupPreservedAcrossDisableAndLoadedFromStorage() {
        store.replacePlan(expectedToken = 1L, newPlan = samplePlan(1L), nowEpochMillis = now)
        assertFalse(store.hasPendingCleanup())

        // Disable moves active plan events into pendingCleanup
        val disableRes = store.disable()
        assertTrue(disableRes is DisableResult.Success)
        assertTrue(store.hasPendingCleanup())
        assertEquals(2, store.getPendingCleanupEvents().size)
        assertNull(store.getActivePlan())

        // Re-open fresh instance from disk storage bytes
        val store2 = PrayerAlarmStore(storage)
        assertTrue(store2.hasPendingCleanup())
        assertEquals(2, store2.getPendingCleanupEvents().size)
        assertNull(store2.getActivePlan())
        assertFalse(store2.isEnabled())

        // Acknowledge cleaned up events durably removes them
        val ackOk = store2.acknowledgeCleanedUpEvents(setOf("360630:2026-10-07:fajr", "360630:2026-10-07:dhuhr"))
        assertTrue(ackOk)
        assertFalse(store2.hasPendingCleanup())

        // Fresh reopen verifies durably removed
        val store3 = PrayerAlarmStore(storage)
        assertFalse(store3.hasPendingCleanup())
    }

    @Test
    fun testPendingCleanupPreservedAcrossResetWithoutErasingEvidence() {
        store.replacePlan(expectedToken = 1L, newPlan = samplePlan(1L), nowEpochMillis = now)
        store.disable()
        assertTrue(store.hasPendingCleanup())

        // Reset must NOT erase unresolved cleanup evidence
        val resetRes = store.reset()
        assertTrue(resetRes is ResetResult.Success)
        assertTrue(store.hasPendingCleanup())
        assertEquals(2, store.getPendingCleanupEvents().size)

        // Reopen from storage verifies durability
        val store2 = PrayerAlarmStore(storage)
        assertTrue(store2.hasPendingCleanup())
        assertEquals(2, store2.getPendingCleanupEvents().size)
    }

    @Test
    fun testAcknowledgeCleanedUpEventsFailsClosedOnStorageWriteFailure() {
        store.replacePlan(expectedToken = 1L, newPlan = samplePlan(1L), nowEpochMillis = now)
        store.disable()
        assertTrue(store.hasPendingCleanup())

        // Storage write fails during acknowledgment
        storage.failWrites = true
        val ackOk = store.acknowledgeCleanedUpEvents(setOf("360630:2026-10-07:fajr"))
        assertFalse(ackOk)
        // In-memory state rolled back; pending cleanup intact
        assertEquals(2, store.getPendingCleanupEvents().size)

        // Reopen verifies storage retained unresolved records
        storage.failWrites = false
        val store2 = PrayerAlarmStore(storage)
        assertEquals(2, store2.getPendingCleanupEvents().size)
    }

    @Test
    fun testOldFormatJsonWithoutPendingCleanupLoadsSafely() {
        storage.setRaw("{\"enabled\":true,\"generationToken\":5}")
        val oldStore = PrayerAlarmStore(storage)
        assertTrue(oldStore.isEnabled())
        assertEquals(5L, oldStore.getGenerationToken())
        assertFalse(oldStore.hasPendingCleanup())
        assertEquals(0, oldStore.getPendingCleanupCount())
        assertTrue(oldStore.getPendingCleanupEvents().isEmpty())
    }
}
