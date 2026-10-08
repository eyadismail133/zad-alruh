package dev.zadalruh.zad_alruh

import dev.zadalruh.zad_alruh.alarm.AlarmTriggerType
import dev.zadalruh.zad_alruh.alarm.CanonicalPrayer
import dev.zadalruh.zad_alruh.alarm.PlanValidationResult
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmMode
import dev.zadalruh.zad_alruh.alarm.PrayerEventRecord
import dev.zadalruh.zad_alruh.alarm.PrayerPlanValidator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PrayerPlanValidationTest {

    private val now = 1760000000000L // arbitrary fixed test instant

    private fun createValidRawPlan(
        expectedToken: Long = 1L,
        cityId: Int = 360630,
        cityNameAr: String = "القاهرة",
        timezone: String = "Africa/Cairo",
        generalVoiceId: String = "adam",
        fajrVoiceId: String = "malmo_fajr",
        mode: String = "full_adhan",
        coverageHorizonUtc: Long = now + 864000000L,
        events: List<Map<String, Any>> = listOf(
            mapOf(
                "eventKey" to "360630:2026-10-07:fajr",
                "prayerKey" to "fajr",
                "calculationCivilDate" to "2026-10-07",
                "triggerEpochMillis" to now + 3600000L,
                "voiceId" to "malmo_fajr",
                "mode" to "full_adhan"
            ),
            mapOf(
                "eventKey" to "360630:2026-10-07:dhuhr",
                "prayerKey" to "dhuhr",
                "calculationCivilDate" to "2026-10-07",
                "triggerEpochMillis" to now + 18000000L,
                "voiceId" to "adam",
                "mode" to "full_adhan"
            )
        )
    ): Map<String, Any> {
        return mapOf(
            "expectedToken" to expectedToken,
            "cityId" to cityId,
            "cityNameAr" to cityNameAr,
            "timezone" to timezone,
            "generalVoiceId" to generalVoiceId,
            "fajrVoiceId" to fajrVoiceId,
            "mode" to mode,
            "coverageHorizonUtc" to coverageHorizonUtc,
            "events" to events
        )
    }

    @Test
    fun testValidPlanPassesValidation() {
        val raw = createValidRawPlan()
        val result = PrayerPlanValidator.validate(raw, now)
        assertTrue(result is PlanValidationResult.Valid)
        val valid = (result as PlanValidationResult.Valid).plan
        assertEquals(360630, valid.cityId)
        assertEquals("القاهرة", valid.cityNameAr)
        assertEquals(2, valid.events.size)
        assertEquals("360630:2026-10-07:fajr", valid.events[0].eventKey)
    }

    @Test
    fun testRejectInvalidCityId() {
        val raw = createValidRawPlan(cityId = 0)
        val result = PrayerPlanValidator.validate(raw, now)
        assertTrue(result is PlanValidationResult.Invalid)
        assertEquals("INVALID_CITY_ID", (result as PlanValidationResult.Invalid).errorCode)
    }

    @Test
    fun testRejectInvalidGeneralVoice() {
        // malmo_fajr is not allowed as general adhan voice
        val raw = createValidRawPlan(generalVoiceId = "malmo_fajr")
        val result = PrayerPlanValidator.validate(raw, now)
        assertTrue(result is PlanValidationResult.Invalid)
        assertEquals("INVALID_GENERAL_VOICE", (result as PlanValidationResult.Invalid).errorCode)
    }

    @Test
    fun testRejectNonCanonicalPrayerLikeSunrise() {
        val events = listOf(
            mapOf(
                "eventKey" to "360630:2026-10-07:sunrise",
                "prayerKey" to "sunrise",
                "calculationCivilDate" to "2026-10-07",
                "triggerEpochMillis" to now + 7200000L,
                "voiceId" to "adam",
                "mode" to "full_adhan"
            )
        )
        val raw = createValidRawPlan(events = events)
        val result = PrayerPlanValidator.validate(raw, now)
        assertTrue(result is PlanValidationResult.Invalid)
        assertEquals("INVALID_PRAYER_KEY", (result as PlanValidationResult.Invalid).errorCode)
    }

    @Test
    fun testRejectInvalidCivilDateFormat() {
        val events = listOf(
            mapOf(
                "eventKey" to "360630:07-10-2026:fajr",
                "prayerKey" to "fajr",
                "calculationCivilDate" to "07-10-2026", // Invalid format (should be YYYY-MM-DD)
                "triggerEpochMillis" to now + 3600000L,
                "voiceId" to "adam",
                "mode" to "full_adhan"
            )
        )
        val raw = createValidRawPlan(events = events)
        val result = PrayerPlanValidator.validate(raw, now)
        assertTrue(result is PlanValidationResult.Invalid)
        assertEquals("INVALID_CIVIL_DATE", (result as PlanValidationResult.Invalid).errorCode)
    }

    @Test
    fun testRejectPastEventBeyondTolerance() {
        val events = listOf(
            mapOf(
                "eventKey" to "360630:2026-10-07:fajr",
                "prayerKey" to "fajr",
                "calculationCivilDate" to "2026-10-07",
                "triggerEpochMillis" to now - 120000L, // 2 minutes in the past
                "voiceId" to "adam",
                "mode" to "full_adhan"
            )
        )
        val raw = createValidRawPlan(events = events)
        val result = PrayerPlanValidator.validate(raw, now)
        assertTrue(result is PlanValidationResult.Invalid)
        assertEquals("PAST_EVENT_REJECTED", (result as PlanValidationResult.Invalid).errorCode)
    }

    @Test
    fun testRejectDuplicateEventKey() {
        val events = listOf(
            mapOf(
                "eventKey" to "360630:2026-10-07:fajr",
                "prayerKey" to "fajr",
                "calculationCivilDate" to "2026-10-07",
                "triggerEpochMillis" to now + 3600000L,
                "voiceId" to "adam",
                "mode" to "full_adhan"
            ),
            mapOf(
                "eventKey" to "360630:2026-10-07:fajr",
                "prayerKey" to "fajr",
                "calculationCivilDate" to "2026-10-07",
                "triggerEpochMillis" to now + 3600000L,
                "voiceId" to "adam",
                "mode" to "full_adhan"
            )
        )
        val raw = createValidRawPlan(events = events)
        val result = PrayerPlanValidator.validate(raw, now)
        assertTrue(result is PlanValidationResult.Invalid)
        assertEquals("DUPLICATE_EVENT_KEY", (result as PlanValidationResult.Invalid).errorCode)
    }

    @Test
    fun testRejectEventsListExceedingMaxBound() {
        val events = (1..65).map { i ->
            mapOf(
                "eventKey" to "360630:2026-10-07:fajr$i",
                "prayerKey" to "fajr",
                "calculationCivilDate" to "2026-10-07",
                "triggerEpochMillis" to now + (i * 1000L),
                "voiceId" to "adam",
                "mode" to "full_adhan"
            )
        }
        val raw = createValidRawPlan(events = events)
        val result = PrayerPlanValidator.validate(raw, now)
        assertTrue(result is PlanValidationResult.Invalid)
        assertEquals("PLAN_EVENTS_BOUND_EXCEEDED", (result as PlanValidationResult.Invalid).errorCode)
    }

    @Test
    fun testDeterministicRequestCodeUniqueness() {
        val event1 = PrayerEventRecord(
            eventKey = "360630:2026-10-07:fajr",
            prayerKey = "fajr",
            calculationCivilDate = "2026-10-07",
            triggerEpochMillis = now + 1000L,
            voiceId = "adam",
            mode = PrayerAlarmMode.FULL_ADHAN.key
        )
        val event2 = PrayerEventRecord(
            eventKey = "360630:2026-10-07:dhuhr",
            prayerKey = "dhuhr",
            calculationCivilDate = "2026-10-07",
            triggerEpochMillis = now + 2000L,
            voiceId = "adam",
            mode = PrayerAlarmMode.FULL_ADHAN.key
        )

        val code1Exact = event1.getPendingIntentRequestCode(AlarmTriggerType.EXACT)
        val code1Comp = event1.getPendingIntentRequestCode(AlarmTriggerType.COMPANION)
        val code2Exact = event2.getPendingIntentRequestCode(AlarmTriggerType.EXACT)
        val code2Comp = event2.getPendingIntentRequestCode(AlarmTriggerType.COMPANION)

        assertTrue(code1Exact >= 0)
        assertTrue(code1Comp >= 0)
        assertNotEquals(code1Exact, code1Comp)
        assertNotEquals(code1Exact, code2Exact)
        assertNotEquals(code1Comp, code2Comp)
    }
}
