# Android Native Prayer Alarm and Full-Adhan Architecture Contract

**Version:** 1.0.0<br>
**Target Platform:** Android (minSdk 26, targetSdk 36)<br>
**MethodChannel Name:** `dev.zadalruh.zad_alruh/prayer_alarm`<br>
**Native Owner Package:** `dev.zadalruh.zad_alruh`

---

## 1. Architectural Overview & Single Native Owner Principle

In accordance with the Sol6.1 approved architecture (Oct 06 & Oct 07 corrections), **ONE** custom native Android owner manages all prayer alarm deliveries, persistence, background media playback, and boot restoration.

- **No Kotlin Prayer Engine:** Dart pure planner computes and supplies the UTC future event plan. Native code validates the shape, allowed enums, bounds, and monotonic authorization, and schedules OS alarms.
- **Single Owner Ownership:** Neither `flutter_local_notifications` nor any second scheduling plugin registers Android alarm receivers or boot listeners.
- **Default Disabled:** Fresh installations start with native alarms strictly disabled (`enabled = false`, `generationToken = 1L`). Alarms only schedule when Dart explicitly supplies an authorized plan after user activation.
- **Zero Background Full Playback from Inexact/Boot/Update:** Inexact companion alarms, device reboot (`BOOT_COMPLETED`), and package update (`MY_PACKAGE_REPLACED`) receivers never launch foreground services or play audio. They restore future pending alarms or post short notification alerts only.

```
       +-------------------------------------------------------------+
       |                        Dart Layer                           |
       |  (PrayerCalculator, SelectedCity, UserPreferences, Horizon) |
       +-------------------------------------------------------------+
                                      |
                           MethodChannel Bridge
                      dev.zadalruh.zad_alruh/prayer_alarm
                                      |
                                      v
       +-------------------------------------------------------------+
       |                  MainActivity & Coordinator                 |
       +-------------------------------------------------------------+
               |                                           |
               v                                           v
    +----------------------+                    +--------------------+
    |   PrayerAlarmStore   |                    |   AlarmManager &   |
    |  - Monotonic Token   |                    |   Notifications    |
    |  - Active Plan       |                    |  - Exact RTC_WAKE  |
    |  - Consumed Ledger   |                    |  - Companion Inex  |
    +----------------------+                    |  - 3 Sound Channels|
               |                                +--------------------+
               v                                           |
    +------------------------------------------------------+
    |              PrayerAlarmReceiver                     |
    |  - Checks Store & Token                              |
    |  - Evaluates Delivery State Machine                  |
    +------------------------------------------------------+
               |                                      |
         Exact Granted                       Exact Denied / Fallback
               v                                      v
    +---------------------------+              +---------------------+
    | AdhanMediaPlaybackService |              | PrayerNotification  |
    |  - Android 15+ FGS start  |              | Helper              |
    |  - Audio focus & silent   |              |  - Short alert clip |
    |  - FlutterLoader MP3 play |              |    (Adam, Atcovi,   |
    |  - Stop action            |              |     Malmo Fajr)     |
    +---------------------------+              +---------------------+
```

---

## 2. MethodChannel Bridge API Specification

### 2.1 `getAuthorizationToken`
Returns the current monotonic native authorization token held in the native store.
Dart must fetch this token before preparing a plan replacement to ensure atomic Compare-And-Swap (CAS).

- **Arguments:** `null`
- **Return Type:** `Map<String, Any?>`
  ```json
  {
    "token": 1
  }
  ```

---

### 2.2 `replacePlan`
Atomically replaces the persisted prayer alarm schedule using CAS on `expectedToken`.
**Validate + CAS First Invariant:** Native code validates the full plan structure and executes atomic Compare-And-Swap on the durable store **BEFORE** modifying any `AlarmManager` alarms. If the token is stale or storage persistence fails, no active OS alarms are cancelled or modified. Only upon verified CAS success are previous alarms cancelled and new exact/companion alarms registered.
**Durable Cleanup Migration & Retry:** Previous active plan events are atomically migrated into durable `pendingCleanup` within the same CAS storage transaction. The coordinator immediately attempts to cancel all pending cleanup events (cancelling both OS alarms and posted notifications). Confirmed cancellations are durably acknowledged (`store.acknowledgeCleanedUpEvents(...)`) and removed from disk. Any events whose OS cancellation fails remain safely persisted in `pendingCleanup` across app restarts and store reopens until subsequent calls confirm cancellation.
**Paired Registration Counting:** `scheduledCount` reflects true per-event paired registrations:
- When exact alarms are permitted (`canScheduleExactAlarms == true`), an event only increments `scheduledCount` if **both** its exact alarm and companion alarm succeed.
- When exact alarms are denied (`canScheduleExactAlarms == false`), an event increments `scheduledCount` if its companion alarm succeeds.
- Diagnostic fields `exactScheduledCount` and `companionScheduledCount` record raw successful registrations, while `scheduledCount` guarantees that an event is never falsely reported as scheduled if only one half of a required alarm pair succeeded.

- **Arguments:**
  ```json
  {
    "expectedToken": 1,
    "cityId": 360630,
    "cityNameAr": "القاهرة",
    "timezone": "Africa/Cairo",
    "generalVoiceId": "adam",
    "fajrVoiceId": "malmo_fajr",
    "mode": "full_adhan",
    "coverageHorizonUtc": 1791500000000,
    "events": [
      {
        "eventKey": "360630:2026-10-07:fajr",
        "prayerKey": "fajr",
        "calculationCivilDate": "2026-10-07",
        "triggerEpochMillis": 1791435600000,
        "voiceId": "malmo_fajr",
        "mode": "full_adhan"
      },
      {
        "eventKey": "360630:2026-10-07:dhuhr",
        "prayerKey": "dhuhr",
        "calculationCivilDate": "2026-10-07",
        "triggerEpochMillis": 1791460800000,
        "voiceId": "adam",
        "mode": "full_adhan"
      }
    ]
  }
  ```

- **Validation Rules (enforced in native Kotlin):**
  - `expectedToken`: Must match current `generationToken` exactly.
  - `cityId`: Must be a positive integer (`> 0`).
  - `cityNameAr`: Non-empty Arabic name.
  - `timezone`: Valid non-empty IANA string.
  - `generalVoiceId`: Allowed values: `"adam"`, `"atcovi"`.
  - `fajrVoiceId`: Allowed values: `"adam"`, `"atcovi"`, `"malmo_fajr"`.
  - `mode`: `"full_adhan"` or `"short_alert"`.
  - `events`: List of events, `0 <= size <= 60`.
  - `events[*].prayerKey`: Must be one of `fajr`, `dhuhr`, `asr`, `maghrib`, `isha` (strictly excluding `sunrise`).
  - `events[*].calculationCivilDate`: Must match `^\d{4}-\d{2}-\d{2}$`.
  - `events[*].eventKey`: Must equal `"$cityId:$calculationCivilDate:$prayerKey"`.
  - `events[*].triggerEpochMillis`: Must be future instant (tolerance: now - 60 seconds).
  - `events[*].voiceId`: Must be permitted for that prayer type (only Fajr may use `malmo_fajr`).

- **Success Return:**
  ```json
  {
    "success": true,
    "token": 2,
    "scheduledCount": 48,
    "attemptedCount": 48,
    "exactScheduledCount": 48,
    "companionScheduledCount": 48,
    "exactAlarmsUsed": true,
    "companionAlarmsUsed": true,
    "messageAr": "تم تحديث جدول مواعيد الصلاة بنجاح"
  }
  ```
  *(Note: For a valid plan with 0 upcoming events, returns `success: true`, `scheduledCount: 0`, `attemptedCount: 0`, `exactAlarmsUsed: false`, `companionAlarmsUsed: false`)*

- **Partial Failure Return (AlarmManager Scheduling Incomplete / Cancellation Failure):**
  If any upcoming event fails to schedule (exact or companion) or previous alarms fail to cancel, native storage has already committed the plan (`authorizationInvalidated: true`), but the call returns `success: false` and `partialFailure: true` to prevent Dart caller from assuming full OS alarm registration:
  ```json
  {
    "success": false,
    "authorizationInvalidated": true,
    "token": 2,
    "partialFailure": true,
    "errorCode": "ALARM_SCHEDULING_INCOMPLETE",
    "scheduledCount": 40,
    "attemptedCount": 48,
    "exactScheduledCount": 40,
    "companionScheduledCount": 48,
    "exactAlarmsUsed": true,
    "companionAlarmsUsed": true,
    "messageAr": "تم تحديث الخطة، ولكن تعذر اكتمال جدولة بعض التنبيهات في النظام."
  }
  ```
  *(Note: `exactAlarmsUsed` is strictly `exactScheduledCount > 0` and `companionAlarmsUsed` is `companionScheduledCount > 0`, reflecting actual OS alarms registered rather than permission state. Any uncancelled previous events remain durably persisted in `pendingCleanup` for subsequent retries).*

- **Failure Return (Stale Token / Invalidation):**
  ```json
  {
    "success": false,
    "errorCode": "STALE_AUTHORIZATION_TOKEN",
    "messageAr": "انتهت صلاحية رمز التفويض، يرجى إعادة محاولة جدولة المواعيد.",
    "currentToken": 3
  }
  ```

- **Failure Return (Validation / Storage):**
  ```json
  {
    "success": false,
    "errorCode": "INVALID_PRAYER_KEY",
    "messageAr": "نوع الصلاة غير صالح أو غير معتمد (الشروق غير مشمول).",
    "detail": "prayerKey 'sunrise' at index 2 is invalid; canonical prayers only"
  }
  ```

---

### 2.3 `disableAlarms`
Disables prayer alarms and stops any active adhan playback service.
**Crucial Invariant:** The native generation token is incremented (`generationToken + 1`), active plan events are atomically migrated into durable `pendingCleanup`, and the plan is cleared (`activePlan = null`, `enabled = false`) in storage **BEFORE** OS alarm cancellation and service termination take place. Any in-flight plan computed with an earlier token cannot re-enroll.
**Durable Cleanup Retry:** The coordinator attempts cancellation of all unresolved `pendingCleanup` events across both `AlarmSchedulerGateway.cancelAlarms(ev)` and `NotificationGateway.cancelEventNotification(ev.eventKey)`. Confirmed cancellations are durably acknowledged (`store.acknowledgeCleanedUpEvents(...)`) and removed from disk. If storage persistence during acknowledgement fails or OS cancellation fails, unresolved cleanup identities remain durably persisted across store reopens and app restarts for subsequent retries.
If OS cleanup encounters errors (e.g., failure cancelling alarms, cancelling notifications, or stopping service), native storage invalidation remains committed, but the method returns `success: false` with `authorizationInvalidated: true` and `partialFailure: true` to prevent Dart callers from assuming that all OS alarms and notifications are eliminated.

- **Arguments:** `null`
- **Return Type (Success):**
  ```json
  {
    "success": true,
    "authorizationInvalidated": true,
    "token": 3,
    "messageAr": "تم تعطيل مواعيد الأذان وإلغاء التنبيهات بنجاح"
  }
  ```
- **Return Type (Partial Failure in OS Cleanup):**
  ```json
  {
    "success": false,
    "authorizationInvalidated": true,
    "token": 3,
    "partialFailure": true,
    "errorCode": "OS_CLEANUP_INCOMPLETE",
    "errorMessageAr": "تعذر إلغاء بعض التنبيهات من النظام ولكن تم إيقاف خطة الأذان بنجاح",
    "oldAlarmsCancelled": false,
    "serviceStopPending": false
  }
  ```

---

### 2.4 `resetAll`
Invalidates authorization token, disables alarms, cancels pending OS alarms, stops active service, and wipes the durable consumed ledger and persisted active plan.
**Crucial Invariant:** Monotonic token invalidation, active plan event migration into `pendingCleanup`, and ledger clearing are durably committed to storage **BEFORE** OS cancellations.
**Cleanup Evidence Preservation:** `resetAll` clears `consumedLedger` and `activePlan`, but strictly **retains uncancelled `pendingCleanup` records**. Unresolved cleanup identities are never wiped or discarded on reset, ensuring that future calls can continue attempting OS cancellations and that the system never falsely reports complete cleanup while OS alarms remain live.
If OS cleanup fails (unresolved alarms, notifications, or service stop), returns `success: false` with `authorizationInvalidated: true`, `partialFailure: true`, and the fresh incremented token.

- **Arguments:** `null`
- **Return Type (Success):**
  ```json
  {
    "success": true,
    "authorizationInvalidated": true,
    "token": 4,
    "messageAr": "تمت إعادة ضبط جدول مواعيد الأذان بالكامل"
  }
  ```
- **Return Type (Partial Failure in OS Cleanup):**
  ```json
  {
    "success": false,
    "authorizationInvalidated": true,
    "token": 4,
    "partialFailure": true,
    "errorCode": "OS_CLEANUP_INCOMPLETE",
    "errorMessageAr": "تعذر إلغاء بعض التنبيهات من النظام ولكن تم تصفير إعدادات الأذان بنجاح",
    "oldAlarmsCancelled": false,
    "serviceStopPending": false
  }
  ```

---

### 2.5 `getState`
Returns current native diagnostic state for UI rendering and permission checks.

- **Return Type:**
  ```json
  {
    "enabled": true,
    "generationToken": 2,
    "canScheduleExactAlarms": true,
    "notificationsAllowed": true,
    "isServiceRunning": false,
    "isManualPlaybackLeaseActive": false,
    "futureEventsCount": 48,
    "pendingCleanupCount": 0,
    "cityId": 360630,
    "cityNameAr": "القاهرة",
    "timezone": "Africa/Cairo",
    "coverageHorizonUtc": 1791500000000,
    "consumedLedgerCount": 2
  }
  ```
  *(Note: `pendingCleanupCount` is a non-negative integer indicating the count of unresolved event identities retained in durable store for pending OS alarm and notification cleanup. It aggregates unresolved events across failed plan replacements and cancellations without any speculative cap or dropping of unresolved IDs).*

---

### 2.6 `acquireManualPlaybackLease`
Acquires a process-local mutual exclusion lease for manual foreground audio (such as Quran recitation or adhan preview).
Executes under the shared coordinator physical-start lock (`coordinatorLock`):
1. Confirms immediate synchronous stop and resource release of any active native adhan playback before granting lease.
2. Confirms cancellation of existing owned prayer event notifications (including posted notifications, active short deliveries, and unresolved events tracked in durable `pendingCleanup`) so previous short fallback channel sound has a cancellation request accepted before manual playback begins.
3. Validates `requestId` is bounded (`<= 256` chars) and non-blank.
4. Binds the lease to the current Flutter engine session identity.
5. An existing live owner lease is strictly protected and cannot be overwritten by a new request. If already leased, rejects with `LEASE_BUSY`, except genuine idempotent retry for the exact same session and `requestId`.
6. Dart physical player queue retires previous player and releases old lease before requesting a new lease.

- **Arguments:**
  ```json
  {
    "requestId": "quran_surah_1_reciter_minshawi"
  }
  ```

- **Success Return:**
  ```json
  {
    "acquired": true,
    "leaseToken": "lease_4f81c9a0-826d-476c-8433-289db22101ab"
  }
  ```

- **Idempotent Return (Same Session & RequestId):**
  ```json
  {
    "acquired": true,
    "leaseToken": "lease_4f81c9a0-826d-476c-8433-289db22101ab",
    "idempotent": true
  }
  ```

- **Busy Return (Live Lease Held by Another Request):**
  ```json
  {
    "acquired": false,
    "errorCode": "LEASE_BUSY",
    "messageAr": "يوجد إذن تشغيل يدوي نشط حالياً لم يتم تحريره."
  }
  ```

- **Failed Stop Return (Native Service Stop Unconfirmed):**
  ```json
  {
    "acquired": false,
    "errorCode": "NATIVE_SERVICE_STOP_FAILED",
    "messageAr": "تعذر تأكيد إيقاف تشغيل الأذان النشط."
  }
  ```

- **Failed Notification Cancellation Return (Notification Cancellation Unconfirmed):**
  ```json
  {
    "acquired": false,
    "errorCode": "NOTIFICATION_CANCEL_FAILED",
    "messageAr": "تعذر تأكيد إلغاء تنبيهات الصلاة النشطة."
  }
  ```

---

### 2.7 `releaseManualPlaybackLease`
Releases an active manual playback lease under `coordinatorLock`.
- Clears the lease **ONLY** if `leaseToken` matches the currently held lease token.
- Stale or redundant releases from past owners or retired players are harmless no-ops (`cleared: false, reason: "token_mismatch"`), strictly preserving the active replacement lease of a newer owner.
- Unconfirmed stop retains the lease.
- In-flight or temporary engine detach does not clear the lease; if engine recreation occurs, new engine sees `LEASE_BUSY` until previous confirmed player retirement.
- Process death clears the in-memory lease together with the foreground player (lease is not persisted to disk).
- **No Automatic Replay on Release:** Prayers that triggered during manual listening are durably recorded in terminal `MANUAL_SUPPRESSED`; releasing the lease does not replay missed audio.

- **Arguments:**
  ```json
  {
    "leaseToken": "lease_4f81c9a0-826d-476c-8433-289db22101ab"
  }
  ```

- **Success Return:**
  ```json
  {
    "released": true,
    "cleared": true
  }
  ```

- **Mismatched / Stale Token Return (No-Op):**
  ```json
  {
    "released": true,
    "cleared": false,
    "reason": "token_mismatch"
  }
  ```

- **Absent Lease Return:**
  ```json
  {
    "released": true,
    "cleared": false,
    "reason": "no_active_lease"
  }
  ```

---

### 2.8 `stopActivePlayback` (Manual Quran/Adhan Handoff)
Used by Flutter before initiating manual in-app Quran recitation or adhan preview audio.
Invokes `AdhanMediaPlaybackService.stopActiveInstance()` directly under `coordinatorLock`:
- Synchronously releases the active `MediaPlayer` and reset states.
- Abandons system audio focus.
- Removes the foreground status notification and triggers `stopSelf()`.
- Executes without sleeping on the main UI thread, polling loops, or starting unnecessary background services.
- Confirmed resource release status is returned directly to Dart.
- Cancels existing owned prayer event notifications under lock (including posted notifications, active short deliveries, and unresolved events tracked in durable `pendingCleanup`) to terminate any playing short notification channel audio.
- Returns `true` only if both service stop and owned notification cancellations are confirmed.

- **Return Type:**
  ```json
  {
    "stopped": true
  }
  ```

---

### 2.9 Permission Functions
- `canScheduleExactAlarms`: Returns `Boolean`.
- `canPostNotifications`: Returns `Boolean`.
- `requestExactAlarmPermission`: On Android 12+ (API 31+), launches system settings (`ACTION_REQUEST_SCHEDULE_EXACT_ALARM`) for the app package. Never invoked automatically; requires explicit user action in UI.
- `requestNotificationPermission`: On Android 13+ (API 33+), requests runtime `POST_NOTIFICATIONS` permission. Never invoked automatically on app launch.

---

## 3. Durable Consumed Ledger & Delivery State Machine

### 3.1 Event Identity & Ledger Retention
- Every canonical event is uniquely identified by:
  $$\text{eventKey} = \text{cityId} : \text{calculationCivilDate} : \text{prayerKey}$$
- **Persistence Across Generations:** When settings change (e.g. voice change from Adam to Atcovi, minute offset adjustment, or foreground app refresh) for the **SAME** city and civil date, the consumed ledger record is **strictly retained**.
- This architectural rule prevents replay: if Fajr on `2026-10-07` has already been delivered, changing settings in the afternoon will not re-trigger or double-sound Fajr.
- **Bounded Retention:** Entries older than 14 days that do not belong to the active plan's upcoming events are pruned during plan replacement.

### 3.2 State Transitions

```
[ UNCLAIMED / PENDING ]
       |
       +---> Manual playback lease active (in-app Quran/audio playing)
       |     --> Transitions to MANUAL_SUPPRESSED (durable terminal state)
       |     --> Posts ONE dedicated silent prayer notification (zad_alruh_prayer_manual_silent)
       |     --> Zero audible alert, no service launch, no replay on lease release
       |
       +---> Exact alarm fires on time (Permissions granted, Mode=full_adhan)
       |     --> Transitions to EXACT_CLAIMED
       |     --> Starts AdhanMediaPlaybackService
       |            |
       |            +--> startForeground() called (Android 15+ compliance)
       |            +--> Checks silent/DND & Requests Audio Focus
       |            |       |
       |            |       +--> Focus Granted
       |            |       |       --> Manual lease acquired concurrently?
       |            |       |               YES --> Transitions to MANUAL_SUPPRESSED & stops
       |            |       |               NO  --> Transitions to PLAY_CLAIMED (durable pre-start claim)
       |            |       |                       --> mediaPlayer.start()
       |            |       |                       --> Transitions to FULL_CONSUMED (permanently consumed)
       |            |       |
       |            |       +--> Focus Denied / Silent / Channel blocked
       |            |               --> Within 5min lateness window?
       |            |                   YES --> Transitions to SHORT_DELIVERED (short fallback once)
       |            |                   NO  --> Transitions to SUPPRESSED_OR_FAILED
       |            |               --> Service stops immediately
       |
       +---> Companion alarm fires (or Exact with denied permission / short_alert mode)
             --> Transitions to SHORT_DELIVERED
             --> Posts short notification alert once
```

### 3.3 Race Condition Handling & Resilience Invariants
1. **Exact-First:** Exact alarm fires $\to$ `EXACT_CLAIMED` $\to$ `PLAY_CLAIMED` $\to$ `FULL_CONSUMED`. Companion fires 10s later $\to$ inspects ledger $\to$ sees `FULL_CONSUMED` $\to$ drops immediately. **Zero double sound.**
2. **Companion-First:** Exact permission denied $\to$ Companion fires $\to$ `SHORT_DELIVERED`. Exact fires later $\to$ sees `SHORT_DELIVERED` $\to$ drops immediately. **Zero double sound.**
3. **Concurrent Execution:** Atomic synchronized lock on the native ledger ensures only one thread claims delivery. Exactly one sound path executes.
4. **Fail-Closed Persistence (Finding 1):** Every state transition explicitly validates the outcome of `store.updateConsumedRecord(...)`. If storage persistence fails, the state machine returns `AlarmProcessingOutcome.PersistenceFailure`, and coordinator/service emit **zero** audible or notification side effects.
5. **45-Second Companion Offset (Finding 7):**
   - When exact alarms are permitted, companion alarms are scheduled at $t + 45\text{s}$ ($45,000\text{ms}$). This gives exact alarm delivery and FGS startup precedence, while providing a reliable fallback within the 5-minute lateness window if the exact delivery is abandoned.
   - When exact alarms are denied by the OS or user, companion inexact alarms are scheduled directly at the scheduled event instant ($t$).
6. **Early Trigger Guard (Finding 7):** If an alarm broadcast arrives $> 5\text{s}$ before scheduled trigger time (`now < trigger - 5s`), it is rejected as `TriggerTooEarly`. The event remains unconsumed and pending.
7. **Process Death / Crash Gap & One-Way PLAY_CLAIMED Invariant:**
   - If process dies after `EXACT_CLAIMED` before service starts (a failure known before possible start where sound was proven impossible): after 30 seconds of abandonment and within the 5-minute lateness window, companion delivers short fallback **once**, transitioning to `SHORT_DELIVERED`. Full adhan is **never** replayed.
   - If process dies after `PLAY_CLAIMED` before or during `mediaPlayer.start()`, or if `FULL_CONSUMED` persistence fails after physical start: because durable `PLAY_CLAIMED` signifies that physical full playback may have started or is already audible, this transition is strictly **one-way: NO short fallback and NO full replay**. Companion wake-up or future alarms return `AlreadyDelivered` and drop without sound. The system strictly prefers an ambiguous missed reminder over double sound.
   - Once `FULL_CONSUMED` is marked, subsequent failures cannot rewrite state or emit short fallback.
8. **5-Minute Lateness Window:** If an alarm triggers $> 5$ minutes after scheduled instant, it transitions to `EXPIRED_LATE` and drops without sound.
9. **Manual Playback Exclusivity & MANUAL_SUPPRESSED Terminal State:**
   - When an eligible prayer alarm triggers while a manual playback lease is active, or if a lease is acquired concurrently after service launch but before physical start, the event transitions to terminal `MANUAL_SUPPRESSED`.
   - Transitions to `MANUAL_SUPPRESSED` are permitted **ONLY** for `PENDING` (unclaimed) or known pre-start `EXACT_CLAIMED` states. It never rewrites `PLAY_CLAIMED`, `FULL_CONSUMED`, `SHORT_DELIVERED`, `EXPIRED_LATE`, or `SUPPRESSED_OR_FAILED`.
   - Durably persisting `MANUAL_SUPPRESSED` precedes any notification. If ledger persistence fails, zero notification and zero audible effects are emitted.
   - Upon successful persistence, exactly one dedicated silent notification is posted (`zad_alruh_prayer_manual_silent`).
   - Companion duplicate alarms observe terminal `MANUAL_SUPPRESSED` and drop without sound or duplicate notification.
   - Releasing the manual lease does not replay or re-trigger the suppressed prayer.

---

## 4. Android 15+ Foreground Service & Media Playback Specification

- **Foreground Service Type:** `mediaPlayback` (`android:foregroundServiceType="mediaPlayback"`).
- **Manual Playback Lease Exclusivity & Lock Synchronization:**
  - `acquireManualPlaybackLease`, `releaseManualPlaybackLease`, `handleServicePrestartFailure`, `authorizeAndStartPlayback`, and `stopActiveAdhanPlayback` are strictly synchronized under the coordinator's shared `coordinatorLock`.
  - An acquire request cannot overwrite an existing live owner lease, preventing conflicting playback sessions.
  - Native service stop and existing owned prayer event notification cancellation are confirmed before granting any lease.
  - Dedicated silent channel: `zad_alruh_prayer_manual_silent` (Importance: `LOW`, no sound, no vibration, badge enabled).
  - Arabic notification text:
    `أثناء الاستماع داخل التطبيق يظهر تنبيه الصلاة بدون تشغيل صوت آخر؛ تشغيل الأذان التلقائي لا يعاد بعد انتهاء الاستماع.`
  - System sound control note: User-modified notification channels, OS DND, and system volume are Android OS-controlled and require on-device verification; tests verify internal coordinator, state-machine, and ledger exclusivity.
- **Unified Locked Pre-Start Failure Protocol (`handleServicePrestartFailure`):**
  - **Single Production Coordinator Locked Handler:** Every service pre-start failure branch is routed through `coordinator.handleServicePrestartFailure(token, eventKey, reason)`:
    1. `manual_playback_lease_active`: Manual lease active at service startup.
    2. `start_foreground_failed`: `startForeground` exception (e.g. Android 14+ FGS restriction).
    3. `suppressed_by_silent_dnd_or_status_channel`: Silent/DND mode or playback status channel blocked.
    4. `audio_focus_denied`: System audio focus denied by AudioManager.
    5. `media_player_prepare_failed`: Media asset loading or preparation failure.
    6. `service_launch_failed`: Background service launch failure from alarm broadcast receiver.
  - **Critical Race Elimination:** Holding `coordinatorLock` across the entire evaluation prevents a race condition where `acquireManualPlaybackLease` could be granted between volatile lease check and audible notification emission.
  - **Atomic Evaluation Invariants:**
    - If a manual playback lease is active: eligible pre-start claim transitions to `MANUAL_SUPPRESSED` and emits **ONE** dedicated silent notice (`zad_alruh_prayer_manual_silent`); zero audible sound.
    - If no manual lease is active: transitions to `SHORT_DELIVERED` via `stateMachine.handleServiceStartupFailure` and emits **ONE** short audible alert, provided the event's voice channel is not blocked and trigger is within the 5-minute lateness window.
    - If storage persistence fails: returns `false` with **ZERO** notification effects (fail-closed).
    - If event is in terminal state (`FULL_CONSUMED`, `SHORT_DELIVERED`, `EXPIRED_LATE`, `MANUAL_SUPPRESSED`) or `PLAY_CLAIMED`: returns `false` with zero duplicate replay or state overwrite.
- **Synchronized Pre-Start Protocol & Structured Result:**
  Immediately prior to physical `mediaPlayer.start()`, the service executes `coordinator.authorizeAndStartPlayback(...)` under the shared coordinator synchronization lock, returning a typed `PlaybackStartResult`:
  1. Active plan, enabled state, and monotonic authorization token are re-validated immediately before physical start.
  2. Silent / DND / channel suppression is re-checked under the same lock.
  3. `resetAll()` or `disableAlarms()` on the main thread acquires the same lock, ensuring that reset/disable invalidates and confirmed-stops playback cleanly, preventing stale sound after reset.
  4. If physical playback starts but `FULL_CONSUMED` fails to persist in the ledger, the coordinator immediately confirms service stop and returns `PlaybackStartResult.ConsumedRecordPersistenceFailed(eventKey)` (`isFullyDurable == false`). The event remains in `PLAY_CLAIMED`, guaranteeing that no fallback short notification is emitted and no full adhan is replayed (strict at-most-once delivery).
- **Resilient MediaPlayer Lifecycle, Release & Production Cleanup Barrier:**
  `MediaPlayerLifecycleHelper.stopAndRelease(adapter)` and `resetAndRelease(adapter)` execute `stop()`, `reset()`, and `release()` in separate, isolated `try-catch` blocks on a narrow `MediaPlayerLifecycleAdapter`. An exception thrown by `stop()` or `reset()` never bypasses `release()`. If `prepareMediaPlayer` or authorization denial cleanup fails (such as an asset prepare error followed by release failure), the uncleaned player is strictly retained in `AdhanPlaybackSession.failedCleanupBarrier`. Subsequent stop or cleanup calls attempt release across all retained barrier instances and refuse to falsely confirm success (`false`) while any failed player remains unreleased. `stopActiveInstance()` truthfully returns `false` if cleanup was incomplete.
- **Crash-Safe Atomic Storage Replacement:**
  `FileStorageDriver.write` flushes and executes `fd.sync()` before performing an atomic file move (`Files.move(..., ATOMIC_MOVE, REPLACE_EXISTING)`). If `ATOMIC_MOVE` fails or is unsupported, it fails closed, cleans up the temporary file, and returns `false` leaving the old storage file intact. All non-atomic fallbacks (such as ordinary move or `renameTo`) are strictly eliminated to ensure storage files are never partially written or corrupted upon process termination.
- **Justified Manifest Permissions:**
  - `android.permission.POST_NOTIFICATIONS`
  - `android.permission.SCHEDULE_EXACT_ALARM`
  - `android.permission.RECEIVE_BOOT_COMPLETED`
  - `android.permission.FOREGROUND_SERVICE`
  - `android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK`
- **Exemptions:** Started from exact user-scheduled alarms using `AlarmManager.setExactAndAllowWhileIdle(...)` which satisfies the exact alarm background start exemption.
- **Android 15 Call Ordering:** `startForeground(...)` with type `mediaPlayback` is called **before** `AudioManager.requestAudioFocus(...)`.
- **Silent Ongoing Status Notification:**
  - Channel: `"zad_alruh_adhan_playback_status"` (Importance: `LOW`, no sound/vibration).
  - Ongoing: `true`.
  - Action Button: `"إيقاف"` (Stop) $\to$ triggers `PrayerAlarmReceiver.ACTION_STOP_ACTIVE_ADHAN` $\to$ calls `AdhanMediaPlaybackService.stopActiveInstance()`.
- **Three Short Sound Channels:**
  - `"zad_alruh_alert_adam"`: raw resource `adam_alert`
  - `"zad_alruh_alert_atcovi"`: raw resource `atcovi_alert`
  - `"zad_alruh_alert_malmo_fajr"`: raw resource `malmo_fajr_alert`
  - User edits to channels are strictly preserved.
- **Channel & Silent/DND Suppression (Finding 6):**
  - If the silent status channel (`zad_alruh_adhan_playback_status`) is blocked by the user, full adhan playback is prohibited.
  - If the device is in Silent mode, Vibrate mode, or Do Not Disturb (DND), full adhan playback is conservatively suppressed.
  - Rechecked both at service start AND immediately before physical `mediaPlayer.start()`.
  - Suppressed full adhan falls back to short notification alert (obeying notification permissions and channel settings) or drops silently.
- **Audio Assets:**
  - Master full MP3 assets bundled in Flutter assets (`assets/audio/adhan/adam-converted.mp3`, `assets/audio/adhan/atcovi-original.mp3`, `assets/audio/adhan/malmo-fajr-extracted.mp3`).
  - Resolved natively using `FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)` and `context.assets.openFd(key)`. No network or temporary file extraction needed.
  - Asset file descriptors are strictly closed in `finally` blocks.
- **Focus Interruption & Lifecycle:**
  - Focus loss (`AUDIOFOCUS_LOSS`, `AUDIOFOCUS_LOSS_TRANSIENT`) $\to$ stops playback immediately, releases MediaPlayer, no automatic resume.
  - Audio becoming noisy (headphones disconnected) $\to$ stops playback immediately.
  - Service return value $\to$ `START_NOT_STICKY`.

---

## 5. System Boot, Update & Time Change Restoration

- Handled by `PrayerBootReceiver` responding to:
  - `android.intent.action.BOOT_COMPLETED`
  - `android.intent.action.MY_PACKAGE_REPLACED`
  - `android.intent.action.TIME_SET`
  - `android.intent.action.TIMEZONE_CHANGED`
- **Rules:**
  1. Restores **FUTURE** saved UTC events only (`triggerEpochMillis > now`).
  2. Skips already delivered / terminal events in the consumed ledger.
  3. Never plays sound or launches background foreground services.
  4. Force-stopped apps on Android require explicit reopen by the user before alarms are rescheduled by the OS.
  5. Selected city IANA timezone operates independently of the physical device timezone.

---

## 6. Unit Testing & Production Verification Gate

- **Pluggable OS Interfaces:** All Android boundaries (`AlarmSchedulerGateway`, `NotificationGateway`, `ServiceGateway`, `TimeProvider`, `StorageDriver`) are abstracted via interfaces.
- **100% JVM Testability:** State machine transitions, ledger pruning, race conditions, storage driver persistence failures, and alarm scheduling are tested on local JVM without requiring an Android emulator or device.
- **Official Pinned JSON Test Codec:**
  `build.gradle.kts` declares `testImplementation("org.json:json:20260814")` (official JSON-java release) for desktop JVM tests. Android production code uses the platform-provided `org.json` runtime. Android stub mocks throwing `RuntimeException: Stub!` are avoided without altering production behavior.
