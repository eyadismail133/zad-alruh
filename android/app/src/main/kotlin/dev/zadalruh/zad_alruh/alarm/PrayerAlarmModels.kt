package dev.zadalruh.zad_alruh.alarm

import java.util.zip.CRC32

/**
 * Supported canonical daily prayer types.
 * Sunrise is strictly excluded from prayer alarms.
 */
enum class CanonicalPrayer(val key: String, val arabicName: String) {
    FAJR("fajr", "الفجر"),
    DHUHR("dhuhr", "الظهر"),
    ASR("asr", "العصر"),
    MAGHRIB("maghrib", "المغرب"),
    ISHA("isha", "العشاء");

    companion object {
        fun fromKey(key: String): CanonicalPrayer? = entries.firstOrNull { it.key == key }
    }
}

/**
 * Adhan voice identifiers and their bundled asset paths.
 */
object AdhanVoiceRegistry {
    const val VOICE_ADAM = "adam"
    const val VOICE_ATCOVI = "atcovi"
    const val VOICE_MALMO_FAJR = "malmo_fajr"

    val ALLOWED_GENERAL_VOICES = setOf(VOICE_ADAM, VOICE_ATCOVI)
    val ALLOWED_FAJR_VOICES = setOf(VOICE_ADAM, VOICE_ATCOVI, VOICE_MALMO_FAJR)

    // Master full audio bundled in Flutter assets:
    val FULL_AUDIO_ASSET_PATHS = mapOf(
        VOICE_ADAM to "assets/audio/adhan/adam-converted.mp3",
        VOICE_ATCOVI to "assets/audio/adhan/atcovi-original.mp3",
        VOICE_MALMO_FAJR to "assets/audio/adhan/malmo-fajr-extracted.mp3"
    )

    // Sub-30s alert clips in android raw resources:
    val RAW_ALERT_RESOURCE_NAMES = mapOf(
        VOICE_ADAM to "adam_alert",
        VOICE_ATCOVI to "atcovi_alert",
        VOICE_MALMO_FAJR to "malmo_fajr_alert"
    )

    fun isAllowedVoiceForPrayer(voiceId: String, prayerKey: String): Boolean {
        return if (prayerKey == CanonicalPrayer.FAJR.key) {
            ALLOWED_FAJR_VOICES.contains(voiceId)
        } else {
            ALLOWED_GENERAL_VOICES.contains(voiceId)
        }
    }
}

/**
 * Delivery mode for prayer alarms.
 */
enum class PrayerAlarmMode(val key: String) {
    FULL_ADHAN("full_adhan"),
    SHORT_ALERT("short_alert");

    companion object {
        fun fromKey(key: String): PrayerAlarmMode? = entries.firstOrNull { it.key == key }
    }
}

/**
 * Lifecycle state of an individual prayer event in the durable ledger.
 */
enum class DeliveryState(val key: String) {
    PENDING("pending"),
    EXACT_CLAIMED("exact_claimed"),
    PLAY_CLAIMED("play_claimed"),
    FULL_CONSUMED("full_consumed"),
    SHORT_DELIVERED("short_delivered"),
    EXPIRED_LATE("expired_late"),
    SUPPRESSED_OR_FAILED("suppressed_or_failed"),
    MANUAL_SUPPRESSED("manual_suppressed");

    val isTerminal: Boolean
        get() = this == FULL_CONSUMED ||
                this == SHORT_DELIVERED ||
                this == EXPIRED_LATE ||
                this == SUPPRESSED_OR_FAILED ||
                this == MANUAL_SUPPRESSED

    companion object {
        fun fromKey(key: String): DeliveryState = entries.firstOrNull { it.key == key } ?: PENDING
    }
}

/**
 * Trigger source of the alarm.
 */
enum class AlarmTriggerType(val key: String) {
    EXACT("exact"),
    COMPANION("companion");

    companion object {
        fun fromKey(key: String): AlarmTriggerType = entries.firstOrNull { it.key == key } ?: COMPANION
    }
}

/**
 * Single prayer event within a plan.
 */
data class PrayerEventRecord(
    val eventKey: String,
    val prayerKey: String,
    val calculationCivilDate: String,
    val triggerEpochMillis: Long,
    val voiceId: String,
    val mode: String
) {
    val prayer: CanonicalPrayer?
        get() = CanonicalPrayer.fromKey(prayerKey)

    /**
     * Deterministic non-negative 31-bit request code for AlarmManager PendingIntent.
     */
    fun getPendingIntentRequestCode(alarmType: AlarmTriggerType): Int {
        val input = "$eventKey:${alarmType.key}"
        val crc = CRC32()
        crc.update(input.toByteArray(Charsets.UTF_8))
        return (crc.value and 0x7FFFFFFF).toInt()
    }
}

/**
 * Complete prayer schedule plan supplied by Dart.
 */
data class PrayerPlan(
    val expectedToken: Long,
    val cityId: Int,
    val cityNameAr: String,
    val timezone: String,
    val generalVoiceId: String,
    val fajrVoiceId: String,
    val mode: String,
    val coverageHorizonUtc: Long,
    val events: List<PrayerEventRecord>
)

/**
 * Durable record for a prayer event in the consumed ledger.
 */
data class ConsumedRecord(
    val eventKey: String,
    val state: DeliveryState,
    val timestampMillis: Long,
    val deliveryType: String,
    val details: String? = null
)

/**
 * Result of plan validation.
 */
sealed class PlanValidationResult {
    data class Valid(val plan: PrayerPlan) : PlanValidationResult()
    data class Invalid(val errorCode: String, val messageAr: String, val detail: String) : PlanValidationResult()
}

/**
 * Validates the raw map supplied from MethodChannel against strict architectural requirements.
 */
object PrayerPlanValidator {
    private val CIVIL_DATE_REGEX = Regex("""^\d{4}-\d{2}-\d{2}$""")
    const val MAX_PLAN_EVENTS = 60

    fun validate(rawMap: Map<*, *>, nowEpochMillis: Long): PlanValidationResult {
        val expectedToken = (rawMap["expectedToken"] as? Number)?.toLong()
            ?: return PlanValidationResult.Invalid(
                "INVALID_EXPECTED_TOKEN",
                "رمز التفويض المتوقع مفقود أو غير صالح.",
                "expectedToken must be a non-null number"
            )

        val cityId = (rawMap["cityId"] as? Number)?.toInt()
            ?: return PlanValidationResult.Invalid(
                "INVALID_CITY_ID",
                "معرّف المدينة غير صالح.",
                "cityId must be a positive integer"
            )
        if (cityId <= 0) {
            return PlanValidationResult.Invalid(
                "INVALID_CITY_ID",
                "معرّف المدينة يجب أن يكون رقماً موجباً.",
                "cityId must be > 0"
            )
        }

        val cityNameAr = (rawMap["cityNameAr"] as? String)?.trim()
        if (cityNameAr.isNullOrEmpty()) {
            return PlanValidationResult.Invalid(
                "INVALID_CITY_NAME",
                "اسم المدينة باللغة العربية مطلوب.",
                "cityNameAr must be non-empty"
            )
        }

        val timezone = (rawMap["timezone"] as? String)?.trim()
        if (timezone.isNullOrEmpty()) {
            return PlanValidationResult.Invalid(
                "INVALID_TIMEZONE",
                "المنطقة الزمنية للمدينة غير صالحة.",
                "timezone must be non-empty"
            )
        }

        val generalVoiceId: String = (rawMap["generalVoiceId"] as? String)?.trim()
            ?: return PlanValidationResult.Invalid(
                "INVALID_GENERAL_VOICE",
                "صوت الأذان العام المختار غير محدد.",
                "generalVoiceId is missing or null"
            )
        if (!AdhanVoiceRegistry.ALLOWED_GENERAL_VOICES.contains(generalVoiceId)) {
            return PlanValidationResult.Invalid(
                "INVALID_GENERAL_VOICE",
                "صوت الأذان العام المختار غير مدعوم.",
                "generalVoiceId must be one of ${AdhanVoiceRegistry.ALLOWED_GENERAL_VOICES}"
            )
        }

        val fajrVoiceId: String = (rawMap["fajrVoiceId"] as? String)?.trim()
            ?: return PlanValidationResult.Invalid(
                "INVALID_FAJR_VOICE",
                "صوت أذان الفجر المختار غير محدد.",
                "fajrVoiceId is missing or null"
            )
        if (!AdhanVoiceRegistry.ALLOWED_FAJR_VOICES.contains(fajrVoiceId)) {
            return PlanValidationResult.Invalid(
                "INVALID_FAJR_VOICE",
                "صوت أذان الفجر المختار غير مدعوم.",
                "fajrVoiceId must be one of ${AdhanVoiceRegistry.ALLOWED_FAJR_VOICES}"
            )
        }

        val mode: String = (rawMap["mode"] as? String)?.trim()
            ?: return PlanValidationResult.Invalid(
                "INVALID_ALARM_MODE",
                "نمط التنبيه غير محدد.",
                "mode is missing or null"
            )
        if (PrayerAlarmMode.fromKey(mode) == null) {
            return PlanValidationResult.Invalid(
                "INVALID_ALARM_MODE",
                "نمط التنبيه غير مدعوم.",
                "mode must be full_adhan or short_alert"
            )
        }

        val coverageHorizonUtc = (rawMap["coverageHorizonUtc"] as? Number)?.toLong()
            ?: return PlanValidationResult.Invalid(
                "INVALID_COVERAGE_HORIZON",
                "أفق تغطية المواعيد غير صالح.",
                "coverageHorizonUtc must be a valid epoch millisecond timestamp"
            )

        val rawEvents = rawMap["events"] as? List<*>
            ?: return PlanValidationResult.Invalid(
                "INVALID_EVENTS_LIST",
                "قائمة مواعيد الصلاة غير متوفرة.",
                "events must be a list"
            )

        if (rawEvents.size > MAX_PLAN_EVENTS) {
            return PlanValidationResult.Invalid(
                "PLAN_EVENTS_BOUND_EXCEEDED",
                "عدد مواعيد الصلاة يتجاوز الحد الأقصى المسموح به ($MAX_PLAN_EVENTS).",
                "events.size ${rawEvents.size} exceeds $MAX_PLAN_EVENTS"
            )
        }

        val parsedEvents = mutableListOf<PrayerEventRecord>()
        val seenEventKeys = mutableSetOf<String>()
        val seenRequestCodes = mutableSetOf<Int>()

        // 1-minute tolerance for clock skew during plan handoff
        val pastThreshold = nowEpochMillis - 60_000L

        for ((index, rawEvent) in rawEvents.withIndex()) {
            val eventMap = rawEvent as? Map<*, *>
                ?: return PlanValidationResult.Invalid(
                    "INVALID_EVENT_ENTRY",
                    "أحد عناصر مواعيد الصلاة غير صالح.",
                    "event at index $index is not a map"
                )

            val prayerKey = (eventMap["prayerKey"] as? String)?.trim()
            val canonicalPrayer = CanonicalPrayer.fromKey(prayerKey ?: "")
                ?: return PlanValidationResult.Invalid(
                    "INVALID_PRAYER_KEY",
                    "نوع الصلاة غير صالح أو غير معتمد (الشروق غير مشمول).",
                    "prayerKey '$prayerKey' at index $index is invalid; canonical prayers only"
                )

            val calculationCivilDate = (eventMap["calculationCivilDate"] as? String)?.trim() ?: ""
            if (!CIVIL_DATE_REGEX.matches(calculationCivilDate)) {
                return PlanValidationResult.Invalid(
                    "INVALID_CIVIL_DATE",
                    "تاريخ الحساب المدني غير صالح (الصيغة المطلوبة YYYY-MM-DD).",
                    "calculationCivilDate '$calculationCivilDate' at index $index is invalid"
                )
            }

            val triggerEpochMillis = (eventMap["triggerEpochMillis"] as? Number)?.toLong()
                ?: return PlanValidationResult.Invalid(
                    "INVALID_TRIGGER_TIME",
                    "وقت تشغيل التنبيه غير صالح.",
                    "triggerEpochMillis at index $index must be a number"
                )

            if (triggerEpochMillis < pastThreshold) {
                return PlanValidationResult.Invalid(
                    "PAST_EVENT_REJECTED",
                    "لا يمكن جدولة موعد صلاة في الماضي.",
                    "event at index $index is in the past: trigger $triggerEpochMillis < now $nowEpochMillis"
                )
            }

            val eventVoiceId = ((eventMap["voiceId"] as? String)?.trim()) ?: generalVoiceId
            if (!AdhanVoiceRegistry.isAllowedVoiceForPrayer(eventVoiceId, canonicalPrayer.key)) {
                return PlanValidationResult.Invalid(
                    "INVALID_EVENT_VOICE",
                    "صوت الأذان المحدد لصلاة ${canonicalPrayer.arabicName} غير صالح.",
                    "voiceId '$eventVoiceId' not permitted for prayer '${canonicalPrayer.key}' at index $index"
                )
            }

            val eventMode = ((eventMap["mode"] as? String)?.trim()) ?: mode
            if (PrayerAlarmMode.fromKey(eventMode) == null) {
                return PlanValidationResult.Invalid(
                    "INVALID_EVENT_MODE",
                    "نمط التنبيه المحدد للحدث غير صالح.",
                    "event mode '$eventMode' at index $index is invalid"
                )
            }

            val expectedEventKey = "$cityId:$calculationCivilDate:${canonicalPrayer.key}"
            val providedEventKey = (eventMap["eventKey"] as? String)?.trim()
            if (providedEventKey != null && providedEventKey != expectedEventKey) {
                return PlanValidationResult.Invalid(
                    "EVENT_KEY_MISMATCH",
                    "معرّف الحدث غير متطابق مع مفتاح الحساب المدني والمدينة.",
                    "eventKey '$providedEventKey' != expected '$expectedEventKey' at index $index"
                )
            }

            if (seenEventKeys.contains(expectedEventKey)) {
                return PlanValidationResult.Invalid(
                    "DUPLICATE_EVENT_KEY",
                    "تكرار موعد الصلاة لنفس اليوم والمدينة.",
                    "duplicate eventKey '$expectedEventKey' found at index $index"
                )
            }
            seenEventKeys.add(expectedEventKey)

            val record = PrayerEventRecord(
                eventKey = expectedEventKey,
                prayerKey = canonicalPrayer.key,
                calculationCivilDate = calculationCivilDate,
                triggerEpochMillis = triggerEpochMillis,
                voiceId = eventVoiceId,
                mode = eventMode
            )

            // Verify no request code collision across plan
            val exactCode = record.getPendingIntentRequestCode(AlarmTriggerType.EXACT)
            val compCode = record.getPendingIntentRequestCode(AlarmTriggerType.COMPANION)
            if (seenRequestCodes.contains(exactCode) || seenRequestCodes.contains(compCode)) {
                return PlanValidationResult.Invalid(
                    "REQUEST_CODE_COLLISION",
                    "تعارض غير متوقع في معرّفات التنبيهات الدقيقة.",
                    "collision detected for request codes in event '$expectedEventKey'"
                )
            }
            seenRequestCodes.add(exactCode)
            seenRequestCodes.add(compCode)

            parsedEvents.add(record)
        }

        return PlanValidationResult.Valid(
            PrayerPlan(
                expectedToken = expectedToken,
                cityId = cityId,
                cityNameAr = cityNameAr,
                timezone = timezone,
                generalVoiceId = generalVoiceId,
                fajrVoiceId = fajrVoiceId,
                mode = mode,
                coverageHorizonUtc = coverageHorizonUtc,
                events = parsedEvents
            )
        )
    }
}
