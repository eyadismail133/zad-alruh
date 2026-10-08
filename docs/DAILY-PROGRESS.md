# Zad Al-Ruh (زاد الروح) - Daily Progress Integration Milestone (Core Architecture)

## 1. Architectural Overview & Schema V3 Migration

The daily progress subsystem tracks five daily devotional tasks:
1. Morning Dhikr (أذكار الصباح): 22 source-based checklist items.
2. Evening Dhikr (أذكار المساء): 20 source-based checklist items.
3. Quran Reading (ورد القرآن): Unique confirmed pages (1..604) against a user-configured goal (1..604, default 2).
4. Post-Prayer Dhikr (أذكار بعد الصلاة): Sourced confirmation from Hisn al-Muslim Chapter 25 (8 entries: items 66..73).
5. Daily Dua (دعاء اليوم): Sourced confirmation linked to an authentic Hisn al-Muslim item (1..267).

### Nondestructive SQLite Schema V3
The application database has been upgraded from `schemaVersion = 2` to `schemaVersion = 3` with zero data loss:
- **Preserved Tables**: All six original tables (`reading_progress`, `bookmarks`, `favorites`, `dhikr_sessions`, `daily_progress`, `user_preferences`) and existing columns (including `general_adhan_voice` and `fajr_adhan_voice`) are preserved intact across fresh installations and upgrades from v1/v2.
- **New Tables in V3**:
  1. `hisn_daily_item_progress`:
     - Key: `(date_bucket, period, item_id)`
     - Columns: `is_completed` (0 or 1), `updated_at`.
     - Constraints: `CHECK (length(date_bucket) > 0 AND instr(date_bucket, '|') > 0)`, `CHECK (period IN ('morning', 'evening', 'shared_100'))`, `CHECK (item_id >= 1 AND item_id <= 267)`.
  2. `daily_quran_pages`:
     - Key: `(date_bucket, page_number)`
     - Columns: `confirmed_at`.
     - Constraints: `CHECK (length(date_bucket) > 0 AND instr(date_bucket, '|') > 0)`, `CHECK (page_number >= 1 AND page_number <= 604)`.
  3. `daily_source_confirmations`:
     - Key: `(date_bucket, task_key)`
     - Columns: `hisn_item_id` (nullable, 1..267), `is_completed` (0 or 1), `updated_at`.
     - Constraints: `CHECK (length(date_bucket) > 0 AND instr(date_bucket, '|') > 0)`, `CHECK (task_key IN ('daily_dua', 'post_prayer'))`.
- **Legacy Row Policy**: Ambiguous and destructive deletion of legacy bare-date rows (`YYYY-MM-DD`) has been completely eliminated. Legacy bare rows coexist with qualified rows (`IANA|YYYY-MM-DD`). Qualified exact-key state takes precedence, and legacy booleans/counts are retained as explicitly labelled historical metadata (`legacyMorningDhikrCompleted`, `legacyQuranCompleted`, etc.), never polluting current task completion.

---

## 2. Tracked Mutation Barrier & Reset Fence

The reset pipeline enforces a strict, synchronous barrier preventing data resurrection, deadlocks, and corrupted persistence:

```
[User invokes resetAllState()]
           │
           ▼
1. Synchronously fence new writes (mutationBarrier.beginReset())
   - Increments generation counter.
   - Rejects ALL subsequent mutation acceptances synchronously across all families.
   - Enforces single-owner reset token.
           │
           ▼
2. Prepare in-memory controllers
   - Reading controller advances generation and gates new intents.
           │
           ▼
3. Drain pre-reset accepted operations (with Timeout Guard)
   - Await preferences queue, reading write chain, and tracked repo mutations.
   - If drain exceeds timeout (default 5s, configurable override), throws TimeoutException.
   - Timeout aborts reset BEFORE audio stop, native boundary, or SQLite wipe.
   - Failure path releases owner fence (endReset(success: false)) and restores usability.
   - Delayed operations awaiting validators/DB recheck captured generation and abort.
           │
           ▼
4. Await external boundaries
   - Await adhanAudioController.stop().
   - Await nativeAlarmResetBoundary.resetAll() ('dev.zadalruh.zad_alruh/prayer_alarm').
   - IF EITHER FAILS:
       - Abort reset.
       - Restore barrier permissions (mutationBarrier.endReset(success: false)).
       - Restore reading controller (cancelReset()).
       - SQLite persistence is 100% UNTOUCHED.
           │
           ▼
5. Atomic SQLite deletion
   - Delete all 9 tables in ONE transaction.
   - Reinsert clean defaults (reading progress page 1, default preferences).
           │
           ▼
6. Invalidate views and finalize
   - Invalidate Riverpod providers.
   - Reading controller sets default state (page 1).
   - Release barrier (mutationBarrier.endReset(success: true)).
```

### Initializer Concurrency & Generation Guard (getReadingProgress & getPreferences)
- Both `getReadingProgress()` and `getPreferences()` register in `_barrier.runTrackedMutation` synchronously at method invocation.
- If the database table is empty, a transactional `insert-if-absent` (`ConflictAlgorithm.ignore`) followed by a requery is performed. This completely eliminates race conditions where two concurrent initializers could overwrite each other with stale defaults.
- Generation checks (`_barrier.checkGeneration`) execute after `await _db`, after `await db.query`, inside the transaction, and after the transaction. An initializer awaiting SQLite across a reset is safely cancelled by generation mismatch and will never overwrite freshly reset defaults.

### Controller Write Queue FIFO Serialization & Stale Retry Invalidation
- All daily progress controllers (`HisnDailyItemProgressController`, `DailyQuranPagesController`, `DailySourceConfirmationController`) serialize mutations through a private FIFO `_writeQueue`.
- Each mutation creates an immutable intent capturing the sequential counter (`seq`) and the reset generation at invocation time.
- After every `await` (repository write and repository reload query), the controller verifies `!_isDisposed && intent.generation == currentGeneration && intent.seq >= _latestAcceptedSeq` immediately BEFORE publishing state or save errors. Stale reloads from earlier sequence taps can never overwrite newer user intents.
- Failed intents immutably preserve their initial generation. When `retryFailedIntent()` is called, it verifies that the failed intent's generation matches `currentGeneration`. If a reset occurred in the interim, the stale intent is discarded as a no-op, mutating zero rows in SQLite.
- Disposed controllers reject new mutations and retries without entering loading state or mutating SQLite.

### Native Alarm Reset Boundary Contract
- Communicates over MethodChannel `'dev.zadalruh.zad_alruh/prayer_alarm'` via method `'resetAll'`.
- Enforces complete success: requires `success == true`, `partialFailure != true`, and no incomplete cleanup or error codes (`errorCode != 'OS_CLEANUP_INCOMPLETE'`, `errorCode != 'ALARM_SCHEDULING_INCOMPLETE'`, and no non-null failure error code).
- The `authorizationInvalidated` flag is informational (confirming old native alarm authorizations were revoked), NOT a failure condition. It can coexist with complete success (`success: true`, `token: newToken`) or partial failure.
- User-facing error messages are strictly stable Arabic (`NativeResetException.messageArabic`), while raw SDK exceptions, platform codes, and incomplete cleanup statuses are isolated in `technicalCode`.
- Any failure aborts SQLite deletion, preserves all local database persistence, and restores barrier write permissions.

---

## 3. Authoritative Hisn Daily Catalog

The canonical selection of items is centralized in `HisnDailyCatalog`:
- **Chapter 27 (أذكار الصباح والمساء - Items 75..98)**:
  - **Common Items (19)**: 75..92 and 98.
  - **Morning Checklist (22)**: 19 common + 93, 94, 95.
  - **Evening Checklist (20)**: 19 common + 97.
  - **Shared Daily 100-Times Item (Item 96)**: أستغفر الله وأتوب إليه مائة مرة. Tracked once separately, strictly excluded from morning (22) and evening (20) denominators.
  - **Item 92**: `repeatTarget` is null in the source asset (conditional 10 or 1). No invented counter is synthesized.
  - **Item 75**: Preserves preface and Hadith of Anas footnote (ID 101).
- **Chapter 25 (أذكار بعد الصلاة - Items 66..73)**:
  - Exactly 8 items for post-prayer dhikr.
- **Verbatim Footnote Linkage**:
  - No authored or rewritten editorial strings exist in the catalog.
  - Footnote mappings strictly point to source footnote IDs:
    - Item 77: Notes 104, 105.
    - Item 78: Note 107.
    - Item 80: Note 111.
    - Item 81: Note 113.
    - Item 89: Notes 122, 123.
    - Item 90: Note 125.
  - Eventual UI renders verbatim Arabic text from `HisnItem.footnotes`.
- **Verbatim Disclaimer**:
  > «تسجيل قراءة شخصية للمتابعة اليومية، وليس إيجاباً أو توثيقاً شعائرياً ملزماً.»

---

## 4. Date Readiness & Timezone Contract

- **Storage Format**: Stable timezone-qualified key `IANA/Zone|YYYY-MM-DD` (or `YYYY-MM-DD|IANA/Zone`), validated against real calendar dates and recognized IANA timezones.
- **Zero Cairo Guesses**: Before user preferences are hydrated, `dateReadinessProvider` reports `status: DateReadinessStatus.loading` with `isReady == false`. No arbitrary timezone is guessed.
- **Timezone Retention**: Last known validated timezone survives preferences refresh or transient errors.
- **Timezone Switching**: Switching timezones (e.g. Cairo to Riyadh) rebinds the active date bucket and isolates daily progress per zone on the same calendar day.
- **Midnight & Resume**: Active bucket automatically updates upon midnight rollover (via scheduled timer) and app foreground resumption.
- **Immutable Acceptance**: Buckets, item IDs, page numbers, and completed booleans are captured immutably at user invocation and retry, preventing rebinding across midnight or timezone changes.

---

## 5. Five Daily Tasks Semantics & Undo

1. **Morning & Evening Dhikr**:
   - Status is derived **solely** from the 22 / 20 source checks.
   - An empty new dataset evaluates to 0 and `false`, even if an older legacy bare-date record had `true`.
   - Undoing the last checked item returns the count to 0 and status to `false`. It never restores legacy booleans.
2. **Quran Reading**:
   - Status is derived **solely** from unique confirmed pages (1..604) in `daily_quran_pages` reaching `quranGoalPages`.
   - Swiping or opening pages does not count; only explicit confirmation records a page.
   - Confirming a page is idempotent; repeated confirmation of the same page does not increase count.
   - Changing the Quran goal (1..604) recalculates today's completion status from existing confirmed pages without altering page IDs.
3. **Post-Prayer Dhikr**:
   - Explicit confirmation records a self-report row in `daily_source_confirmations` under task key `post_prayer`.
   - Optionally links to a valid item from Chapter 25 (66..73).
4. **Daily Dua**:
   - Explicit confirmation records a self-report row in `daily_source_confirmations` under task key `daily_dua`.
   - Requires choosing a valid authentic Hisn al-Muslim item (1..267) when confirmed.
   - Undoing retains the chosen item ID for convenient re-confirmation.

---

## 6. Public APIs & Controller Contracts

| Provider / Notifier | Type | Methods / Signature | Purpose |
|---------------------|------|---------------------|---------|
| `hisnDailyItemProgressControllerProvider(key)` | `AsyncValue<List<HisnDailyItemProgress>>` | `setItemProgress({required int itemId, required bool isCompleted})`<br>`retryFailedIntent()`<br>`retry()` | Per-item morning/evening checklist tracking with FIFO order, intent capture, and retry. |
| `dailyQuranPagesControllerProvider(bucket)` | `AsyncValue<Set<int>>` | `confirmPage(int pageNumber)`<br>`undoPage(int pageNumber)`<br>`retryFailedIntent()`<br>`retry()` | Daily unique confirmed Quran pages (1..604). |
| `dailySourceConfirmationControllerProvider(key)` | `AsyncValue<DailySourceConfirmation?>` | `setConfirmation({required bool isCompleted, int? hisnItemId})`<br>`retryFailedIntent()`<br>`retry()` | Source-linked confirmation for Daily Dua & Post-Prayer. |
| `preferencesControllerProvider` | `AsyncValue<UserPreferences>` | `setQuranGoal(int goal)`<br>`resetAllState({NativeAlarmResetBoundary? nativeBoundaryOverride})` | User preferences, goal bounds (1..604), and full reset coordinator. |
| `dateReadinessProvider` | `DateReadiness` | `isReady`, `status`, `activeBucket`, `validatedTimezone` | Reactive readiness gating for date-sensitive mutations. |
| `resetBarrierProvider` | `ProgressMutationBarrier` (ChangeNotifier) | `isResetInProgress`, `isAudioStartAllowed`, `currentGeneration` | Synchronous write gating and reactive playback guard. |
| `dailyProgressControllerProvider(bucket)` | `AsyncValue<DailyProgress>` | `toggleTask(...)`<br>`retry()` | Aggregated daily progress and five-task completion status. |
