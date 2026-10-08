package dev.zadalruh.zad_alruh.alarm

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Pluggable durable storage driver interface.
 */
interface StorageDriver {
    fun read(): String?
    fun write(content: String): Boolean
}

/**
 * Production file storage driver that performs atomic writes via temporary files.
 */
class FileStorageDriver(private val storeFile: File) : StorageDriver {
    override fun read(): String? {
        return try {
            if (storeFile.exists() && storeFile.isFile && storeFile.canRead()) {
                storeFile.readText(Charsets.UTF_8)
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    override fun write(content: String): Boolean {
        val parent = storeFile.parentFile ?: return false
        if (!parent.exists() && !parent.mkdirs() && !parent.exists()) {
            return false
        }
        val tempFile = File(parent, "${storeFile.name}.tmp")
        return try {
            FileOutputStream(tempFile).use { fos ->
                fos.write(content.toByteArray(Charsets.UTF_8))
                fos.flush()
                fos.fd.sync()
            }
            try {
                Files.move(
                    tempFile.toPath(),
                    storeFile.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING
                )
                true
            } catch (_: Exception) {
                // Remove all non-atomic fallback (no ordinary move or renameTo).
                // If ATOMIC_MOVE fails or is unsupported, fail closed with old file unchanged.
                tempFile.delete()
                false
            }
        } catch (_: Exception) {
            tempFile.delete()
            false
        }
    }
}

/**
 * Result outcomes for store operations.
 */
sealed class ReplacePlanResult {
    data class Success(val newToken: Long, val scheduledEventsCount: Int) : ReplacePlanResult()
    data class StaleToken(val currentToken: Long) : ReplacePlanResult()
    data class PersistenceFailure(val messageAr: String) : ReplacePlanResult()
}

sealed class DisableResult {
    data class Success(val newToken: Long) : DisableResult()
    data class PersistenceFailure(val messageAr: String) : DisableResult()
}

sealed class ResetResult {
    data class Success(val newToken: Long) : ResetResult()
    data class PersistenceFailure(val messageAr: String) : ResetResult()
}

/**
 * Atomic durable native store for prayer alarm state, generation tokens, active plan,
 * and the consumed event ledger.
 */
class PrayerAlarmStore(private val storageDriver: StorageDriver) {
    private val lock = ReentrantLock()

    // State properties
    private var enabled: Boolean = false
    private var generationToken: Long = 1L
    private var activePlan: PrayerPlan? = null
    private val consumedLedger: MutableMap<String, ConsumedRecord> = mutableMapOf()
    private val pendingCleanup: MutableMap<String, PrayerEventRecord> = mutableMapOf()

    init {
        loadFromStorage()
    }

    private fun loadFromStorage() {
        val jsonString = storageDriver.read() ?: return
        try {
            val root = JSONObject(jsonString)
            enabled = root.optBoolean("enabled", false)
            generationToken = root.optLong("generationToken", 1L)

            val planObj = root.optJSONObject("activePlan")
            if (planObj != null) {
                val rawEvents = planObj.optJSONArray("events") ?: JSONArray()
                val parsedEvents = mutableListOf<PrayerEventRecord>()
                for (i in 0 until rawEvents.length()) {
                    val ev = rawEvents.optJSONObject(i) ?: continue
                    parsedEvents.add(
                        PrayerEventRecord(
                            eventKey = ev.getString("eventKey"),
                            prayerKey = ev.getString("prayerKey"),
                            calculationCivilDate = ev.getString("calculationCivilDate"),
                            triggerEpochMillis = ev.getLong("triggerEpochMillis"),
                            voiceId = ev.getString("voiceId"),
                            mode = ev.getString("mode")
                        )
                    )
                }

                activePlan = PrayerPlan(
                    expectedToken = planObj.optLong("expectedToken", generationToken),
                    cityId = planObj.getInt("cityId"),
                    cityNameAr = planObj.getString("cityNameAr"),
                    timezone = planObj.getString("timezone"),
                    generalVoiceId = planObj.getString("generalVoiceId"),
                    fajrVoiceId = planObj.getString("fajrVoiceId"),
                    mode = planObj.getString("mode"),
                    coverageHorizonUtc = planObj.getLong("coverageHorizonUtc"),
                    events = parsedEvents
                )
            }

            val ledgerObj = root.optJSONObject("consumedLedger")
            consumedLedger.clear()
            if (ledgerObj != null) {
                val keys = ledgerObj.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    val recordObj = ledgerObj.optJSONObject(k) ?: continue
                    consumedLedger[k] = ConsumedRecord(
                        eventKey = recordObj.getString("eventKey"),
                        state = DeliveryState.fromKey(recordObj.getString("state")),
                        timestampMillis = recordObj.getLong("timestampMillis"),
                        deliveryType = recordObj.getString("deliveryType"),
                        details = if (recordObj.has("details") && !recordObj.isNull("details")) recordObj.getString("details") else null
                    )
                }
            }

            val cleanupArr = root.optJSONArray("pendingCleanup")
            pendingCleanup.clear()
            if (cleanupArr != null) {
                for (i in 0 until cleanupArr.length()) {
                    val evObj = cleanupArr.optJSONObject(i) ?: continue
                    val record = PrayerEventRecord(
                        eventKey = evObj.getString("eventKey"),
                        prayerKey = evObj.getString("prayerKey"),
                        calculationCivilDate = evObj.getString("calculationCivilDate"),
                        triggerEpochMillis = evObj.getLong("triggerEpochMillis"),
                        voiceId = evObj.getString("voiceId"),
                        mode = evObj.getString("mode")
                    )
                    pendingCleanup[record.eventKey] = record
                }
            }
        } catch (_: Exception) {
            // Corrupt file recovery: maintain safe initial defaults
            enabled = false
            generationToken = 1L
            activePlan = null
            consumedLedger.clear()
            pendingCleanup.clear()
        }
    }

    private fun serializeToJson(): String {
        val root = JSONObject()
        root.put("enabled", enabled)
        root.put("generationToken", generationToken)

        val plan = activePlan
        if (plan != null) {
            val planObj = JSONObject().apply {
                put("expectedToken", plan.expectedToken)
                put("cityId", plan.cityId)
                put("cityNameAr", plan.cityNameAr)
                put("timezone", plan.timezone)
                put("generalVoiceId", plan.generalVoiceId)
                put("fajrVoiceId", plan.fajrVoiceId)
                put("mode", plan.mode)
                put("coverageHorizonUtc", plan.coverageHorizonUtc)
                val eventsArr = JSONArray()
                for (ev in plan.events) {
                    val evObj = JSONObject().apply {
                        put("eventKey", ev.eventKey)
                        put("prayerKey", ev.prayerKey)
                        put("calculationCivilDate", ev.calculationCivilDate)
                        put("triggerEpochMillis", ev.triggerEpochMillis)
                        put("voiceId", ev.voiceId)
                        put("mode", ev.mode)
                    }
                    eventsArr.put(evObj)
                }
                put("events", eventsArr)
            }
            root.put("activePlan", planObj)
        } else {
            root.put("activePlan", JSONObject.NULL)
        }

        val ledgerObj = JSONObject()
        for ((k, v) in consumedLedger) {
            val recObj = JSONObject().apply {
                put("eventKey", v.eventKey)
                put("state", v.state.key)
                put("timestampMillis", v.timestampMillis)
                put("deliveryType", v.deliveryType)
                if (v.details != null) {
                    put("details", v.details)
                }
            }
            ledgerObj.put(k, recObj)
        }
        root.put("consumedLedger", ledgerObj)

        val cleanupArr = JSONArray()
        for ((_, ev) in pendingCleanup) {
            val evObj = JSONObject().apply {
                put("eventKey", ev.eventKey)
                put("prayerKey", ev.prayerKey)
                put("calculationCivilDate", ev.calculationCivilDate)
                put("triggerEpochMillis", ev.triggerEpochMillis)
                put("voiceId", ev.voiceId)
                put("mode", ev.mode)
            }
            cleanupArr.put(evObj)
        }
        root.put("pendingCleanup", cleanupArr)

        return root.toString()
    }

    fun isEnabled(): Boolean = lock.withLock { enabled }

    fun getGenerationToken(): Long = lock.withLock { generationToken }

    fun getActivePlan(): PrayerPlan? = lock.withLock { activePlan }

    fun getConsumedLedgerSnapshot(): Map<String, ConsumedRecord> = lock.withLock {
        consumedLedger.toMap()
    }

    fun getConsumedRecord(eventKey: String): ConsumedRecord? = lock.withLock {
        consumedLedger[eventKey]
    }

    fun getPendingCleanupEvents(): List<PrayerEventRecord> = lock.withLock {
        pendingCleanup.values.toList()
    }

    fun hasPendingCleanup(): Boolean = lock.withLock {
        pendingCleanup.isNotEmpty()
    }

    fun getPendingCleanupCount(): Int = lock.withLock {
        pendingCleanup.size
    }

    fun acknowledgeCleanedUpEvents(cleanedEventKeys: Set<String>): Boolean = lock.withLock {
        if (cleanedEventKeys.isEmpty()) return true
        val prevCleanup = pendingCleanup.toMutableMap()
        for (key in cleanedEventKeys) {
            pendingCleanup.remove(key)
        }
        val serialized = serializeToJson()
        val ok = storageDriver.write(serialized)
        if (!ok) {
            pendingCleanup.clear()
            pendingCleanup.putAll(prevCleanup)
            return false
        }
        return true
    }

    /**
     * Atomically replaces the current plan via CAS on expectedToken.
     * Preserves consumed ledger across generations for same city/date/prayer.
     * Performs bounded pruning of records older than 14 days without deleting current plan events.
     * Retains previous plan events in pendingCleanup for OS cancellation.
     */
    fun replacePlan(
        expectedToken: Long,
        newPlan: PrayerPlan,
        nowEpochMillis: Long
    ): ReplacePlanResult = lock.withLock {
        if (expectedToken != generationToken) {
            return ReplacePlanResult.StaleToken(generationToken)
        }

        // Advance monotonic generation token
        val newToken = generationToken + 1L

        // Preserve previous state in case persistence fails
        val prevEnabled = enabled
        val prevToken = generationToken
        val prevPlan = activePlan
        val prevLedger = consumedLedger.toMutableMap()
        val prevCleanup = pendingCleanup.toMutableMap()

        // Prune bounded ledger: keep all records for newPlan events, and purge records older than 14 days
        val activeEventKeys = newPlan.events.map { it.eventKey }.toSet()
        val retentionThreshold = nowEpochMillis - (14L * 24L * 3600L * 1000L)
        val iterator = consumedLedger.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            val isCurrentPlanEvent = activeEventKeys.contains(entry.key)
            if (!isCurrentPlanEvent && entry.value.timestampMillis < retentionThreshold) {
                iterator.remove()
            }
        }

        // Retain any old plan events in pendingCleanup
        activePlan?.events?.forEach { ev ->
            pendingCleanup[ev.eventKey] = ev
        }

        enabled = true
        generationToken = newToken
        activePlan = newPlan

        val serialized = serializeToJson()
        val writeSuccess = storageDriver.write(serialized)
        if (!writeSuccess) {
            // Rollback in-memory state on persistence failure
            enabled = prevEnabled
            generationToken = prevToken
            activePlan = prevPlan
            consumedLedger.clear()
            consumedLedger.putAll(prevLedger)
            pendingCleanup.clear()
            pendingCleanup.putAll(prevCleanup)
            return ReplacePlanResult.PersistenceFailure("فشل حفظ خطة المواعيد الجديدة في التخزين الدائم.")
        }

        return ReplacePlanResult.Success(
            newToken = newToken,
            scheduledEventsCount = newPlan.events.size
        )
    }

    /**
     * Updates an individual event record in the consumed ledger atomically.
     */
    fun updateConsumedRecord(record: ConsumedRecord): Boolean = lock.withLock {
        val prevRecord = consumedLedger[record.eventKey]
        consumedLedger[record.eventKey] = record
        val serialized = serializeToJson()
        val ok = storageDriver.write(serialized)
        if (!ok) {
            if (prevRecord != null) {
                consumedLedger[record.eventKey] = prevRecord
            } else {
                consumedLedger.remove(record.eventKey)
            }
        }
        return ok
    }

    /**
     * Invalidates the current generation token and disables alarms.
     * The token generation is incremented BEFORE disable success is reported,
     * ensuring that any in-flight plan cannot re-enroll.
     * Atomically moves any active plan events to pendingCleanup.
     */
    fun disable(): DisableResult = lock.withLock {
        val newToken = generationToken + 1L

        val prevEnabled = enabled
        val prevToken = generationToken
        val prevPlan = activePlan
        val prevCleanup = pendingCleanup.toMutableMap()

        enabled = false
        generationToken = newToken
        activePlan?.events?.forEach { ev ->
            pendingCleanup[ev.eventKey] = ev
        }
        activePlan = null

        val serialized = serializeToJson()
        val ok = storageDriver.write(serialized)
        if (!ok) {
            enabled = prevEnabled
            generationToken = prevToken
            activePlan = prevPlan
            pendingCleanup.clear()
            pendingCleanup.putAll(prevCleanup)
            return DisableResult.PersistenceFailure("فشل حفظ حالة التعطيل في التخزين الدائم.")
        }

        return DisableResult.Success(newToken = newToken)
    }

    /**
     * Invalidates the current generation token, disables alarms, and clears the active plan and ledger.
     * Retains all pendingCleanup records without erasing unresolved cleanup evidence.
     */
    fun reset(): ResetResult = lock.withLock {
        val newToken = generationToken + 1L

        val prevEnabled = enabled
        val prevToken = generationToken
        val prevPlan = activePlan
        val prevLedger = consumedLedger.toMutableMap()
        val prevCleanup = pendingCleanup.toMutableMap()

        enabled = false
        generationToken = newToken
        activePlan?.events?.forEach { ev ->
            pendingCleanup[ev.eventKey] = ev
        }
        activePlan = null
        consumedLedger.clear()

        val serialized = serializeToJson()
        val ok = storageDriver.write(serialized)
        if (!ok) {
            enabled = prevEnabled
            generationToken = prevToken
            activePlan = prevPlan
            consumedLedger.clear()
            consumedLedger.putAll(prevLedger)
            pendingCleanup.clear()
            pendingCleanup.putAll(prevCleanup)
            return ResetResult.PersistenceFailure("فشل إعادة ضبط جدول المواعيد في التخزين الدائم.")
        }

        return ResetResult.Success(newToken = newToken)
    }
}
