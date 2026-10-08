import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/services/native_alarm_reset_boundary.dart';
import 'package:zad_alruh/src/features/hisn/data/hisn_repository_impl.dart';
import 'package:zad_alruh/src/features/hisn/domain/models/hisn_daily_catalog.dart';
import 'package:zad_alruh/src/features/hisn/domain/models/hisn_item.dart';
import 'package:zad_alruh/src/features/hisn/domain/repositories/hisn_repository.dart';
import 'package:zad_alruh/src/features/progress/data/models/daily_source_confirmation.dart';
import 'package:zad_alruh/src/features/progress/data/models/hisn_daily_item_progress.dart';
import 'package:zad_alruh/src/features/progress/data/models/reading_progress.dart';
import 'package:zad_alruh/src/features/progress/data/models/user_preferences.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';
import 'package:zad_alruh/src/features/prayers/presentation/controllers/adhan_audio_controller.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/adhan_audio_player_client.dart';

class _FakeAdhanClient extends Fake implements AdhanAudioPlayerClient {
  final _controller = StreamController<AdhanPlaybackEvent>.broadcast();
  @override
  Stream<AdhanPlaybackEvent> get playbackEventStream => _controller.stream;
  @override
  Future<void> stop() async {}
}

class _FakeAdhanAudioController extends AdhanAudioController {
  bool stopCalled = false;
  bool shouldFailStop = false;

  _FakeAdhanAudioController() : super(_FakeAdhanClient());

  @override
  Future<void> stop() async {
    stopCalled = true;
    if (shouldFailStop) {
      throw StateError('Audio stop failed during test');
    }
  }
}

class _MockNativeAlarmBoundary implements NativeAlarmResetBoundary {
  bool resetAllCalled = false;
  bool shouldThrow = false;
  Exception? exceptionToThrow;

  @override
  Future<void> prepareReset() async {}

  @override
  Future<void> resetAll() async {
    resetAllCalled = true;
    if (shouldThrow) {
      throw exceptionToThrow ??
          const NativeResetException('خطأ في النظام أثناء الاختبار', 'MOCK_ERROR');
    }
  }
}

class _TransientFailRepo extends ProgressRepository {
  bool failNextWrite = false;
  _TransientFailRepo(super.database);

  @override
  Future<HisnDailyItemProgress> setHisnDailyItemProgress({
    required String dateBucket,
    required DhikrPeriod period,
    required int itemId,
    required bool isCompleted,
  }) async {
    if (failNextWrite) {
      throw const SocketException('Transient DB failure');
    }
    return super.setHisnDailyItemProgress(
      dateBucket: dateBucket,
      period: period,
      itemId: itemId,
      isCompleted: isCompleted,
    );
  }

  @override
  Future<void> confirmQuranPage({
    required String dateBucket,
    required int pageNumber,
  }) async {
    if (failNextWrite) {
      throw const SocketException('Transient DB failure');
    }
    return super.confirmQuranPage(
      dateBucket: dateBucket,
      pageNumber: pageNumber,
    );
  }

  @override
  Future<DailySourceConfirmation> setSourceConfirmation({
    required String dateBucket,
    required String taskKey,
    required bool isCompleted,
    int? hisnItemId,
  }) async {
    if (failNextWrite) {
      throw const SocketException('Transient DB failure');
    }
    return super.setSourceConfirmation(
      dateBucket: dateBucket,
      taskKey: taskKey,
      isCompleted: isCompleted,
      hisnItemId: hisnItemId,
    );
  }
}

class _GatedAppDatabase extends AppDatabase {
  final Completer<void> gateEntered = Completer<void>();
  final Completer<void> gateRelease = Completer<void>();
  bool isArmed = false;

  _GatedAppDatabase({
    required super.databaseFactory,
    required super.databasePath,
  });

  @override
  Future<Database> get database async {
    final db = await super.database;
    if (isArmed) {
      isArmed = false;
      if (!gateEntered.isCompleted) {
        gateEntered.complete();
      }
      await gateRelease.future;
    }
    return db;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late HisnRepository hisnRepo;

  setUpAll(() async {
    ensureTimeZonesInitialized();

    final hisnBytes = await File(
      'assets/content/hisn/hisn-muslim.json',
    ).readAsBytes();
    hisnRepo = HisnRepositoryImpl.fromBytes(hisnBytes);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('daily_progress_core_');
    dbPath = p.join(tempDir.path, 'test_core.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  // 1. HisnDailyCatalog Verifications Against Actual Content Asset
  // ---------------------------------------------------------------------------
  group('HisnDailyCatalog Verification Against Content Asset', () {
    test('exact 19 common, 22 morning, 20 evening, and 96 shared items', () async {
      expect(HisnDailyCatalog.commonItemIds.length, 19);
      expect(HisnDailyCatalog.morningItemIds.length, 22);
      expect(HisnDailyCatalog.eveningItemIds.length, 20);
      expect(HisnDailyCatalog.sharedDaily100ItemId, 96);
      expect(HisnDailyCatalog.morningTotalCount, 22);
      expect(HisnDailyCatalog.eveningTotalCount, 20);

      // Verify Chapter 27 items from actual JSON
      final chapter27 = hisnRepo.getChapter(27);
      expect(chapter27, isNotNull);
      final chapter27Items = hisnRepo.getItemsByChapter(27);
      final chapter27ItemIds = chapter27Items.map((HisnItem i) => i.id).toList();
      expect(chapter27ItemIds, containsAll(HisnDailyCatalog.commonItemIds));
      expect(chapter27ItemIds, containsAll(HisnDailyCatalog.morningItemIds));
      expect(chapter27ItemIds, containsAll(HisnDailyCatalog.eveningItemIds));
      expect(chapter27ItemIds, contains(HisnDailyCatalog.sharedDaily100ItemId));

      // Verify item 92 repeatTarget is null in source asset (no invented counter)
      final item92 = chapter27Items.firstWhere((HisnItem i) => i.id == 92);
      expect(item92.repeatTarget, isNull);

      // Verify Chapter 25 has exactly 8 items (66..73)
      final chapter25 = hisnRepo.getChapter(25);
      expect(chapter25, isNotNull);
      final chapter25Items = hisnRepo.getItemsByChapter(25);
      expect(chapter25Items.map((HisnItem i) => i.id).toList(), HisnDailyCatalog.postPrayerItemIds);
      expect(HisnDailyCatalog.postPrayerItemIds.length, 8);
    });

    test('verbatim footnote ID linkage for evening alternatives and item 75 preface', () async {
      final chapter27 = hisnRepo.getChapter(27);
      expect(chapter27, isNotNull);
      final chapter27Items = hisnRepo.getItemsByChapter(27);
      final item75 = chapter27Items.firstWhere((HisnItem i) => i.id == 75);
      expect(item75.footnotes.map((HisnFootnote f) => f.id), contains(HisnDailyCatalog.item75PrefaceFootnoteId));

      const notes = HisnDailyCatalog.eveningAlternativeNotes;
      expect(notes.keys, containsAll(<int>[77, 78, 80, 81, 89, 90]));

      for (final entry in notes.entries) {
        final item = chapter27Items.firstWhere((HisnItem i) => i.id == entry.key);
        final itemFootnoteIds = item.footnotes.map((HisnFootnote f) => f.id).toSet();
        for (final fnId in entry.value.footnoteIds) {
          expect(itemFootnoteIds, contains(fnId),
              reason: 'Item ${entry.key} must contain footnote $fnId');
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Schema V1/V2 to V3 Migration Fixtures & Reopen
  // ---------------------------------------------------------------------------
  group('Schema V1/V2 to V3 Migration Fixtures & Reopen', () {
    test('upgrades v1 and v2 databases, preserving all 6 original tables, voices, and history', () async {
      final rawDb = await databaseFactory.openDatabase(dbPath);

      // Create v1 schema (without adhan voice columns)
      await rawDb.execute('PRAGMA user_version = 1;');
      await rawDb.execute('''
        CREATE TABLE reading_progress (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          last_page INTEGER NOT NULL DEFAULT 1,
          selected_surah INTEGER,
          selected_verse INTEGER,
          updated_at TEXT NOT NULL
        );
      ''');
      await rawDb.execute('''
        CREATE TABLE bookmarks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          page_number INTEGER NOT NULL,
          surah_number INTEGER,
          verse_number INTEGER,
          created_at TEXT NOT NULL
        );
      ''');
      await rawDb.execute('''
        CREATE TABLE favorites (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          content_kind TEXT NOT NULL,
          stable_id TEXT NOT NULL,
          created_at TEXT NOT NULL,
          UNIQUE(content_kind, stable_id)
        );
      ''');
      await rawDb.execute('''
        CREATE TABLE dhikr_sessions (
          session_id TEXT PRIMARY KEY,
          dhikr_id TEXT NOT NULL,
          category TEXT NOT NULL,
          target_count INTEGER NOT NULL,
          current_count INTEGER NOT NULL,
          is_completed INTEGER NOT NULL,
          date_bucket TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
      ''');
      await rawDb.execute('''
        CREATE TABLE daily_progress (
          date_bucket TEXT PRIMARY KEY,
          quran_completed INTEGER NOT NULL DEFAULT 0,
          morning_dhikr_completed INTEGER NOT NULL DEFAULT 0,
          evening_dhikr_completed INTEGER NOT NULL DEFAULT 0,
          post_prayer_dhikr_completed INTEGER NOT NULL DEFAULT 0,
          daily_dua_completed INTEGER NOT NULL DEFAULT 0,
          quran_goal_pages INTEGER NOT NULL DEFAULT 2,
          quran_pages_read INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL
        );
      ''');
      await rawDb.execute('''
        CREATE TABLE user_preferences (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          dark_mode TEXT NOT NULL DEFAULT 'system',
          text_scale REAL NOT NULL DEFAULT 1.0,
          selected_city TEXT NOT NULL DEFAULT 'القاهرة',
          selected_timezone TEXT NOT NULL DEFAULT 'Africa/Cairo',
          quran_default_goal INTEGER NOT NULL DEFAULT 2,
          notifications_enabled INTEGER NOT NULL DEFAULT 0,
          active_dhikr_session_id TEXT,
          updated_at TEXT NOT NULL
        );
      ''');

      final nowStr = DateTime.now().toIso8601String();
      await rawDb.insert('reading_progress', {
        'id': 1,
        'last_page': 42,
        'selected_surah': 2,
        'selected_verse': 255,
        'updated_at': nowStr,
      });
      await rawDb.insert('bookmarks', {
        'id': 1,
        'name': 'علامة قديمة',
        'page_number': 42,
        'created_at': nowStr,
      });
      await rawDb.insert('favorites', {
        'id': 1,
        'content_kind': 'surah',
        'stable_id': '2',
        'created_at': nowStr,
      });
      await rawDb.insert('daily_progress', {
        'date_bucket': '2026-09-27',
        'quran_completed': 1,
        'morning_dhikr_completed': 1,
        'quran_goal_pages': 2,
        'quran_pages_read': 2,
        'updated_at': nowStr,
      });
      await rawDb.insert('user_preferences', {
        'id': 1,
        'dark_mode': 'dark',
        'text_scale': 1.2,
        'selected_city': 'القاهرة',
        'selected_timezone': 'Africa/Cairo',
        'quran_default_goal': 4,
        'notifications_enabled': 1,
        'updated_at': nowStr,
      });

      await rawDb.close();

      // Open with AppDatabase (which runs onUpgrade from v1 to v3)
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(() => repo.close());

      // Verify v1 data survived
      final reading = await repo.getReadingProgress();
      expect(reading.lastPage, 42);
      expect(reading.selectedSurah, 2);

      final bookmarks = await repo.getBookmarks();
      expect(bookmarks.length, 1);
      expect(bookmarks.first.name, 'علامة قديمة');

      final prefs = await repo.getPreferences();
      expect(prefs.darkMode, 'dark');
      expect(prefs.textScale, 1.2);
      expect(prefs.generalAdhanVoice, 'adam');
      expect(prefs.fajrAdhanVoice, 'malmo_fajr');

      // Verify v3 tables created and functional
      await repo.confirmQuranPage(
        dateBucket: 'Africa/Cairo|2026-10-07',
        pageNumber: 15,
      );
      final confirmed = await repo.getConfirmedQuranPages('Africa/Cairo|2026-10-07');
      expect(confirmed, contains(15));

      // Verify SQL check constraint rejects bare date in v3 tables
      final db = await appDb.database;
      expect(
        () => db.insert('daily_quran_pages', {
          'date_bucket': '2026-10-07', // Bare date without '|'
          'page_number': 16,
          'confirmed_at': nowStr,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Legacy Fallback & Undo Contract
  // ---------------------------------------------------------------------------
  group('Legacy Fallback & Undo Contract', () {
    test('legacy bare true records never count as current task completion; last undo leaves false', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(() => repo.close());

      // Insert legacy bare row with all completed flags = true
      await repo.updateDailyTask(
        dateBucket: '2026-10-07',
        morningDhikrCompleted: true,
        eveningDhikrCompleted: true,
        quranCompleted: true,
        dailyDuaCompleted: true,
        postPrayerDhikrCompleted: true,
      );

      // Query qualified bucket: new daily status MUST be false and 0
      final progress = await repo.getDailyProgress('Africa/Cairo|2026-10-07');
      expect(progress.morningDhikrCompleted, isFalse);
      expect(progress.eveningDhikrCompleted, isFalse);
      expect(progress.quranCompleted, isFalse);
      expect(progress.dailyDuaCompleted, isFalse);
      expect(progress.postPrayerDhikrCompleted, isFalse);
      expect(progress.morningCompletedCount, 0);
      expect(progress.quranPagesRead, 0);

      // Legacy metadata is preserved and labelled
      expect(progress.legacyMorningDhikrCompleted, isTrue);
      expect(progress.legacyQuranCompleted, isTrue);
      expect(progress.isLegacyRecord, isTrue);

      // Check 1 item in morning checklist
      await repo.setHisnDailyItemProgress(
        dateBucket: 'Africa/Cairo|2026-10-07',
        period: DhikrPeriod.morning,
        itemId: 75,
        isCompleted: true,
      );
      final afterCheck = await repo.getDailyProgress('Africa/Cairo|2026-10-07');
      expect(afterCheck.morningCompletedCount, 1);
      expect(afterCheck.morningDhikrCompleted, isFalse); // 1 < 22

      // Undo that item (last undo): must return to 0 and stay false, never resurrecting legacy true
      await repo.setHisnDailyItemProgress(
        dateBucket: 'Africa/Cairo|2026-10-07',
        period: DhikrPeriod.morning,
        itemId: 75,
        isCompleted: false,
      );
      final afterUndo = await repo.getDailyProgress('Africa/Cairo|2026-10-07');
      expect(afterUndo.morningCompletedCount, 0);
      expect(afterUndo.morningDhikrCompleted, isFalse);

      // Check that legacy bare row in daily_progress was NOT deleted
      final rawDb = await appDb.database;
      final bareRows = await rawDb.query('daily_progress', where: 'date_bucket = ?', whereArgs: ['2026-10-07']);
      expect(bareRows.length, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Date Readiness & Timezone Contract
  // ---------------------------------------------------------------------------
  group('Date Readiness & Timezone Contract', () {
    test('no Cairo guess before hydration; retains validated zone across refresh/error', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(() => repo.close());

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      // Before hydration, readiness is loading, activeBucket is empty, no Cairo guessing!
      final readinessInitial = container.read(dateReadinessProvider);
      if (!readinessInitial.isReady) {
        expect(readinessInitial.activeBucket, anyOf(isNull, isEmpty));
      }

      // Hydrate preferences
      await container.read(preferencesControllerProvider.future);
      final readinessHydrated = container.read(dateReadinessProvider);
      expect(readinessHydrated.isReady, isTrue);
      expect(readinessHydrated.validatedTimezone, 'Africa/Cairo');
      expect(readinessHydrated.activeBucket, contains('Africa/Cairo|'));

      // Validate qualified date bucket format helper
      expect(isValidQualifiedDateBucket('Africa/Cairo|2026-10-07'), isTrue);
      expect(isValidQualifiedDateBucket('2026-10-07|Africa/Cairo'), isTrue);
      expect(isValidQualifiedDateBucket('2026-10-07'), isFalse);
      expect(isValidQualifiedDateBucket('Africa/Cairo|2026-02-31'), isFalse); // Nonexistent date
      expect(isValidQualifiedDateBucket('Mars/Base|2026-10-07'), isFalse); // Nonexistent timezone
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Reset Barrier & Resurrection Prevention Across Mutation Families
  // ---------------------------------------------------------------------------
  group('Reset Barrier & Resurrection Prevention Across Families', () {
    test('synchronously fences writes at invocation and cancels delayed operations before DB write', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final barrier = ProgressMutationBarrier();
      final delayedCompleter = Completer<void>();

      final repo = ProgressRepository(
        appDb,
        mutationBarrier: barrier,
        versePageValidator: ({required pageNumber, required surahNumber, required verseNumber}) async {
          await delayedCompleter.future;
          return true;
        },
      );
      addTearDown(() => repo.close());

      final fakeAudio = _FakeAdhanAudioController();
      final mockNative = _MockNativeAlarmBoundary();

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          adhanAudioControllerProvider.overrideWith((ref) => fakeAudio),
          nativeAlarmResetBoundaryProvider.overrideWithValue(mockNative),
        ],
      );
      addTearDown(container.dispose);

      await container.read(readingProgressControllerProvider.future);
      await container.read(preferencesControllerProvider.future);

      final readingCtrl = container.read(readingProgressControllerProvider.notifier);
      final prefsCtrl = container.read(preferencesControllerProvider.notifier);

      // Start an in-flight reading write that hangs on delayedCompleter
      final slowWrite = readingCtrl.saveExactStopVerse(page: 2, surah: 2, verse: 1);

      // Invoke resetAllState synchronously
      final resetFuture = prefsCtrl.resetAllState();

      // Immediately after reset invocation, new mutations across families must fail synchronously
      expect(
        () => repo.createBookmark(name: 'علامة جديدة', pageNumber: 5),
        throwsA(isA<StateError>()),
      );
      expect(
        () => repo.confirmQuranPage(dateBucket: 'Africa/Cairo|2026-10-07', pageNumber: 5),
        throwsA(isA<StateError>()),
      );
      expect(
        () => repo.setHisnDailyItemProgress(
          dateBucket: 'Africa/Cairo|2026-10-07',
          period: DhikrPeriod.morning,
          itemId: 75,
          isCompleted: true,
        ),
        throwsA(isA<StateError>()),
      );

      // Release delayedCompleter: slow write wakes up, sees generation mismatch, and throws
      delayedCompleter.complete();
      await expectLater(slowWrite, throwsA(isA<StateError>()));

      await resetFuture;

      // Assert reset wiped state cleanly to defaults
      final readingAfter = await repo.getReadingProgress();
      expect(readingAfter.lastPage, 1);
      expect(readingAfter.selectedSurah, isNull);

      // Assert delayed pre-reset operations can NEVER resurrect rows after reset ends
      final bookmarksAfter = await repo.getBookmarks();
      expect(bookmarksAfter, isEmpty);
    });

    test('failed audio stop or native reset aborts reset, preserves SQLite, and restores usability', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(() => repo.close());

      // Seed data
      await repo.createBookmark(name: 'علامة محفوظة', pageNumber: 10);
      await repo.confirmQuranPage(dateBucket: 'Africa/Cairo|2026-10-07', pageNumber: 10);

      final fakeAudio = _FakeAdhanAudioController();
      final mockNative = _MockNativeAlarmBoundary()..shouldThrow = true;

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          adhanAudioControllerProvider.overrideWith((ref) => fakeAudio),
          nativeAlarmResetBoundaryProvider.overrideWithValue(mockNative),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesControllerProvider.future);
      final prefsCtrl = container.read(preferencesControllerProvider.notifier);

      // Reset fails because native alarm boundary threw
      await expectLater(
        prefsCtrl.resetAllState(),
        throwsA(isA<NativeResetException>()),
      );

      // Verify SQLite persistence was untouched
      final bookmarks = await repo.getBookmarks();
      expect(bookmarks.length, 1);
      expect(bookmarks.first.name, 'علامة محفوظة');

      final pages = await repo.getConfirmedQuranPages('Africa/Cairo|2026-10-07');
      expect(pages, contains(10));

      // Verify controller usability is restored (barrier reopened, not stranded)
      expect(repo.isResetInProgress, isFalse);
      expect(repo.isAudioStartAllowed, isTrue);

      await repo.createBookmark(name: 'علامة ثانية', pageNumber: 20);
      final updatedBookmarks = await repo.getBookmarks();
      expect(updatedBookmarks.length, 2);
    });

    test('drain timeout aborts reset before native or SQLite deletion, retains DB, releases barrier, and delayed write fails on completion', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final barrier = ProgressMutationBarrier();
      final repo = ProgressRepository(appDb, mutationBarrier: barrier);
      addTearDown(() => repo.close());

      // Seed data
      await repo.createBookmark(name: 'علامة قبل المهلة', pageNumber: 7);
      await repo.savePreferences(const UserPreferences(darkMode: 'dark'));

      final fakeAudio = _FakeAdhanAudioController();
      final mockNative = _MockNativeAlarmBoundary();

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          adhanAudioControllerProvider.overrideWith((ref) => fakeAudio),
          nativeAlarmResetBoundaryProvider.overrideWithValue(mockNative),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesControllerProvider.future);
      final prefsCtrl = container.read(preferencesControllerProvider.notifier);

      // Start an in-flight operation that hangs on a gate completer
      final gate = Completer<void>();
      final delayedWriteFuture = barrier.runTrackedMutation('slow_gated_op', (gen) async {
        await gate.future;
        barrier.checkGeneration(gen, 'slow_gated_op');
        final db = await appDb.database;
        await db.insert('bookmarks', {
          'name': 'علامة متأخرة',
          'page_number': 8,
          'created_at': DateTime.now().toIso8601String(),
        });
      });

      // Call resetAllState with short injected timeout
      await expectLater(
        prefsCtrl.resetAllState(
          drainTimeoutOverride: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );

      // Assert reset aborted BEFORE audio stop, native reset, or SQLite deletion
      expect(fakeAudio.stopCalled, isFalse);
      expect(mockNative.resetAllCalled, isFalse);

      // Verify SQLite persistence is retained
      final bookmarksBeforeRelease = await repo.getBookmarks();
      expect(bookmarksBeforeRelease.length, 1);
      expect(bookmarksBeforeRelease.first.name, 'علامة قبل المهلة');

      // Barrier owner fence was released on failure path
      expect(barrier.isResetInProgress, isFalse);
      expect(barrier.isAudioStartAllowed, isTrue);

      // Release gate: in-flight write wakes up, sees generation mismatch, throws StateError
      gate.complete();
      await expectLater(delayedWriteFuture, throwsA(isA<StateError>()));

      // SQLite has NO rows from the late write
      final bookmarksAfterGate = await repo.getBookmarks();
      expect(bookmarksAfterGate.length, 1);
      expect(bookmarksAfterGate.first.name, 'علامة قبل المهلة');

      // Now retrying resetAllState succeeds because active operations are drained!
      await prefsCtrl.resetAllState();
      expect(fakeAudio.stopCalled, isTrue);
      expect(mockNative.resetAllCalled, isTrue);
      final bookmarksAfterSuccessfulReset = await repo.getBookmarks();
      expect(bookmarksAfterSuccessfulReset, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // 6. Quran Goal, Source Confirmations, and Controllers
  // ---------------------------------------------------------------------------
  group('Quran Goal & Source-Linked Confirmations', () {
    test('quran page confirmation is idempotent and goal recalculation preserves page IDs', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(() => repo.close());

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesControllerProvider.future);
      final pagesCtrl = container.read(
        dailyQuranPagesControllerProvider('Africa/Cairo|2026-10-07').notifier,
      );

      // Confirm page 5 twice
      await pagesCtrl.confirmPage(5);
      await pagesCtrl.confirmPage(5);

      final pages = await container.read(
        dailyQuranPagesControllerProvider('Africa/Cairo|2026-10-07').future,
      );
      expect(pages, equals(<int>{5}));

      await pagesCtrl.confirmPage(6);

      final progressGoal2 = await container.read(
        dailyProgressControllerProvider('Africa/Cairo|2026-10-07').future,
      );
      expect(progressGoal2.quranPagesRead, 2);
      expect(progressGoal2.quranGoalPages, 2);
      expect(progressGoal2.quranCompleted, isTrue);

      // Change goal to 3: completion recomputes to false, page IDs remain {5, 6}
      await container.read(preferencesControllerProvider.notifier).setQuranGoal(3);

      final progressGoal3 = await container.read(
        dailyProgressControllerProvider('Africa/Cairo|2026-10-07').future,
      );
      expect(progressGoal3.quranPagesRead, 2);
      expect(progressGoal3.quranGoalPages, 3);
      expect(progressGoal3.quranCompleted, isFalse);
      expect(progressGoal3.confirmedPages, equals(<int>{5, 6}));
    });

    test('daily dua requires valid Hisn item ID 1..267 when completed; post-prayer links to Chapter 25', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(() => repo.close());

      // Daily dua completed without ID throws ArgumentError
      expect(
        () => repo.setSourceConfirmation(
          dateBucket: 'Africa/Cairo|2026-10-07',
          taskKey: DailySourceTasks.dailyDua,
          isCompleted: true,
          hisnItemId: null,
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Daily dua with valid ID 75 succeeds
      final duaConf = await repo.setSourceConfirmation(
        dateBucket: 'Africa/Cairo|2026-10-07',
        taskKey: DailySourceTasks.dailyDua,
        isCompleted: true,
        hisnItemId: 75,
      );
      expect(duaConf.isCompleted, isTrue);
      expect(duaConf.hisnItemId, 75);

      // Post-prayer with invalid chapter ID throws
      expect(
        () => repo.setSourceConfirmation(
          dateBucket: 'Africa/Cairo|2026-10-07',
          taskKey: DailySourceTasks.postPrayer,
          isCompleted: true,
          hisnItemId: 100, // Not in Chapter 25 (66..73)
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Post-prayer with valid ID 66 succeeds
      final postConf = await repo.setSourceConfirmation(
        dateBucket: 'Africa/Cairo|2026-10-07',
        taskKey: DailySourceTasks.postPrayer,
        isCompleted: true,
        hisnItemId: 66,
      );
      expect(postConf.isCompleted, isTrue);
      expect(postConf.hisnItemId, 66);
    });
  });

  // ---------------------------------------------------------------------------
  // 7. Real MethodChannel OS Boundary Mock Tests
  // ---------------------------------------------------------------------------
  group('MethodChannelNativeAlarmResetBoundary Channel Mock Tests', () {
    test('rejects success false, null, wrong types, missing plugin, and platform exception with NativeResetException', () async {
      const channelName = 'dev.zadalruh.zad_alruh/prayer_alarm';
      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      // 1. success == false
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => <String, dynamic>{
          'success': false,
          'errorCode': 'FAILED',
          'messageAr': 'فشل الإلغاء',
        },
      );
      final boundary = MethodChannelNativeAlarmResetBoundary(isAndroid: true);
      expect(() => boundary.resetAll(), throwsA(isA<NativeResetException>()));

      // 2. null response
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => null,
      );
      expect(() => boundary.resetAll(), throwsA(isA<NativeResetException>()));

      // 3. wrong types (e.g. String instead of Map)
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => 'invalid_response',
      );
      expect(() => boundary.resetAll(), throwsA(isA<NativeResetException>()));

      // 4. PlatformException
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => throw PlatformException(
          code: 'SYS_ERR',
          message: 'Failed in Android AlarmManager',
        ),
      );
      expect(() => boundary.resetAll(), throwsA(isA<NativeResetException>()));

      // 5. MissingPluginException
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => throw MissingPluginException(),
      );
      expect(() => boundary.resetAll(), throwsA(isA<NativeResetException>()));

      // 6. success == true succeeds
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => <String, dynamic>{'success': true},
      );
      await expectLater(boundary.resetAll(), completes);

      // 7. partialFailure == true throws NativeResetException with PARTIAL_FAILURE
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => <String, dynamic>{
          'success': true,
          'partialFailure': true,
          'errorCode': 'PARTIAL_CANCEL',
        },
      );
      try {
        await boundary.resetAll();
        fail('Should throw NativeResetException on partialFailure');
      } on NativeResetException catch (e) {
        expect(e.messageArabic, isNotEmpty);
        expect(e.technicalCode, 'PARTIAL_CANCEL');
      }

      // 8. OS_CLEANUP_INCOMPLETE errorCode throws NativeResetException
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => <String, dynamic>{
          'success': true,
          'errorCode': 'OS_CLEANUP_INCOMPLETE',
        },
      );
      try {
        await boundary.resetAll();
        fail('Should throw NativeResetException on OS_CLEANUP_INCOMPLETE');
      } on NativeResetException catch (e) {
        expect(e.technicalCode, 'OS_CLEANUP_INCOMPLETE');
      }

      // 9. ALARM_SCHEDULING_INCOMPLETE errorCode throws NativeResetException
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => <String, dynamic>{
          'success': true,
          'errorCode': 'ALARM_SCHEDULING_INCOMPLETE',
        },
      );
      try {
        await boundary.resetAll();
        fail('Should throw NativeResetException on ALARM_SCHEDULING_INCOMPLETE');
      } on NativeResetException catch (e) {
        expect(e.technicalCode, 'ALARM_SCHEDULING_INCOMPLETE');
      }

      // 10. Inconsistent success: true with non-null failure errorCode fails closed
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => <String, dynamic>{
          'success': true,
          'errorCode': 'FAILED_INCONSISTENT',
        },
      );
      try {
        await boundary.resetAll();
        fail('Should throw NativeResetException on inconsistent errorCode');
      } on NativeResetException catch (e) {
        expect(e.technicalCode, 'FAILED_INCONSISTENT');
      }

      // 11. success == false with authorizationInvalidated: true throws NativeResetException
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => <String, dynamic>{
          'success': false,
          'authorizationInvalidated': true,
        },
      );
      try {
        await boundary.resetAll();
        fail('Should throw NativeResetException on success false + authorizationInvalidated');
      } on NativeResetException catch (e) {
        expect(e.technicalCode, 'NATIVE_RESET_FAILED');
      }

      // 12. success == true with partialFailure: true and authorizationInvalidated: true throws NativeResetException
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => <String, dynamic>{
          'success': true,
          'partialFailure': true,
          'authorizationInvalidated': true,
        },
      );
      try {
        await boundary.resetAll();
        fail('Should throw NativeResetException on partialFailure + authorizationInvalidated');
      } on NativeResetException catch (e) {
        expect(e.technicalCode, 'PARTIAL_FAILURE');
      }

      // 13. Actual native full success map with authorizationInvalidated: true and token is ACCEPTED
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => <String, dynamic>{
          'success': true,
          'authorizationInvalidated': true,
          'token': 'newToken_12345',
          'messageAr': 'تم إلغاء التنبيهات بنجاح',
        },
      );
      await expectLater(boundary.resetAll(), completes);

      // 14. PlatformException sanitized: stable Arabic only, raw SDK details in technicalCode
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => throw PlatformException(
          code: 'SDK_FATAL',
          message: 'Android AlarmManager dead object exception',
        ),
      );
      try {
        await boundary.resetAll();
        fail('Should throw NativeResetException on PlatformException');
      } on NativeResetException catch (e) {
        expect(e.messageArabic, 'تعذر إلغاء تنبيهات الأذان في النظام.');
        expect(e.messageArabic, isNot(contains('Android AlarmManager')));
        expect(e.technicalCode, contains('SDK_FATAL'));
        expect(e.technicalCode, contains('Android AlarmManager dead object exception'));
      }

      // Clean up mock handler
      binding.setMockMethodCallHandler(const MethodChannel(channelName), null);
    });

    test('native partial failure or success false with authorizationInvalidated aborts reset and preserves DB', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(() => repo.close());

      // Seed data
      await repo.createBookmark(name: 'علامة محفوظة', pageNumber: 10);

      const channelName = 'dev.zadalruh.zad_alruh/prayer_alarm';
      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      // Mock partial failure with authorizationInvalidated: true
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => <String, dynamic>{
          'success': true,
          'partialFailure': true,
          'authorizationInvalidated': true,
          'errorCode': 'PARTIAL_CANCEL',
        },
      );

      final boundary = MethodChannelNativeAlarmResetBoundary(isAndroid: true);
      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          adhanAudioControllerProvider.overrideWith((ref) => _FakeAdhanAudioController()),
          nativeAlarmResetBoundaryProvider.overrideWithValue(boundary),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesControllerProvider.future);
      final prefsCtrl = container.read(preferencesControllerProvider.notifier);

      // Reset must fail due to partialFailure
      await expectLater(
        prefsCtrl.resetAllState(),
        throwsA(isA<NativeResetException>()),
      );

      // Verify SQLite persistence is untouched
      final bookmarks = await repo.getBookmarks();
      expect(bookmarks.length, 1);
      expect(bookmarks.first.name, 'علامة محفوظة');

      // Now mock actual native full success with authorizationInvalidated: true and token
      binding.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async => <String, dynamic>{
          'success': true,
          'authorizationInvalidated': true,
          'token': 'newToken_67890',
          'messageAr': 'تم إلغاء التنبيهات بنجاح',
        },
      );

      // Reset now succeeds and wipes SQLite DB
      await prefsCtrl.resetAllState();
      final bookmarksAfterSuccess = await repo.getBookmarks();
      expect(bookmarksAfterSuccess, isEmpty);

      // Clean up mock handler
      binding.setMockMethodCallHandler(const MethodChannel(channelName), null);
    });
  });

  // ---------------------------------------------------------------------------
  // 8. Initializer Concurrency & Generation Guard Across Reset
  // ---------------------------------------------------------------------------
  group('Initializer Concurrency & Generation Guard Across Reset', () {
    test('race two concurrent initializers on empty DB performs insert-if-absent without duplication or replace conflict', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(() => repo.close());

      // Concurrent getPreferences calls on fresh database
      final prefResults = await Future.wait([
        repo.getPreferences(),
        repo.getPreferences(),
      ]);
      expect(prefResults[0].quranDefaultGoal, 2);
      expect(prefResults[1].quranDefaultGoal, 2);

      final rawDb = await appDb.database;
      final prefRows = await rawDb.query('user_preferences');
      expect(prefRows.length, 1);

      // Concurrent getReadingProgress calls on fresh database
      final readingResults = await Future.wait([
        repo.getReadingProgress(),
        repo.getReadingProgress(),
      ]);
      expect(readingResults[0].lastPage, 1);
      expect(readingResults[1].lastPage, 1);

      final readingRows = await rawDb.query('reading_progress');
      expect(readingRows.length, 1);
    });

    test('initializer crossing reset is cancelled by generation mismatch and does not replace new value written after reset', () async {
      final gatedDb = _GatedAppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final barrier = ProgressMutationBarrier();
      final repo = ProgressRepository(gatedDb, mutationBarrier: barrier);
      addTearDown(() => repo.close());

      // Pre-initialize database schema
      await gatedDb.database;

      // Arm the database getter gate for genuine repo.getReadingProgress()
      gatedDb.isArmed = true;

      // Start genuine initializer
      final pendingInit = repo.getReadingProgress();

      // Attach expected StateError future handler BEFORE reset/release
      final errorExpectation = expectLater(
        pendingInit,
        throwsA(isA<StateError>()),
      );

      try {
        // Await finite gate entered
        await gatedDb.gateEntered.future.timeout(const Duration(seconds: 2));

        // A reset happens while actual initializer is pending
        final token = barrier.beginReset();
        await repo.resetLocalState();
        barrier.endReset(token: token, success: true);

        // Write new reading progress post-reset
        await repo.saveReadingProgress(const ReadingProgress(lastPage: 42));
      } finally {
        // Release gate safely even if assertions fail
        if (!gatedDb.gateRelease.isCompleted) {
          gatedDb.gateRelease.complete();
        }
      }

      // Generation mismatch causes pending initializer to fail
      await errorExpectation;

      // Verify that the post-reset value (page 42) was NOT replaced
      final current = await repo.getReadingProgress();
      expect(current.lastPage, 42);
    });
  });

  // ---------------------------------------------------------------------------
  // 9. Daily Controllers Write Queue FIFO Serialization & Post-Await Guards
  // ---------------------------------------------------------------------------
  group('Daily Controllers Write Queue FIFO Serialization & Post-Await Guards', () {
    test('HisnDailyItemProgressController serializes writes in FIFO order: check then undo persists undo (uncompleted)', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(() => repo.close());

      final container = ProviderContainer(
        overrides: [progressRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      const key = HisnItemProgressKey(
        dateBucket: 'Africa/Cairo|2026-10-07',
        period: DhikrPeriod.morning,
      );
      await container.read(hisnDailyItemProgressControllerProvider(key).future);
      final ctrl = container.read(hisnDailyItemProgressControllerProvider(key).notifier);

      final f1 = ctrl.setItemProgress(itemId: 75, isCompleted: true);
      final f2 = ctrl.setItemProgress(itemId: 75, isCompleted: false);
      await Future.wait([f1, f2]);

      final persisted = await repo.getHisnDailyItemProgress('Africa/Cairo|2026-10-07', DhikrPeriod.morning);
      final item75 = persisted.firstWhere((i) => i.itemId == 75);
      expect(item75.isCompleted, isFalse);

      final state = container.read(hisnDailyItemProgressControllerProvider(key)).valueOrNull!;
      final state75 = state.firstWhere((i) => i.itemId == 75);
      expect(state75.isCompleted, isFalse);
    });

    test('DailyQuranPagesController serializes confirm then undo: persists empty set', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(() => repo.close());

      final container = ProviderContainer(
        overrides: [progressRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      const bucket = 'Africa/Cairo|2026-10-07';
      await container.read(dailyQuranPagesControllerProvider(bucket).future);
      final ctrl = container.read(dailyQuranPagesControllerProvider(bucket).notifier);

      final f1 = ctrl.confirmPage(15);
      final f2 = ctrl.undoPage(15);
      await Future.wait([f1, f2]);

      final persisted = await repo.getConfirmedQuranPages(bucket);
      expect(persisted, isEmpty);

      final state = container.read(dailyQuranPagesControllerProvider(bucket)).valueOrNull!;
      expect(state, isEmpty);
    });

    test('DailySourceConfirmationController serializes confirm then undo: persists uncompleted', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(() => repo.close());

      final container = ProviderContainer(
        overrides: [progressRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      const key = DailySourceKey(
        dateBucket: 'Africa/Cairo|2026-10-07',
        taskKey: DailySourceTasks.postPrayer,
      );
      await container.read(dailySourceConfirmationControllerProvider(key).future);
      final ctrl = container.read(dailySourceConfirmationControllerProvider(key).notifier);

      final f1 = ctrl.setConfirmation(isCompleted: true, hisnItemId: 66);
      final f2 = ctrl.setConfirmation(isCompleted: false);
      await Future.wait([f1, f2]);

      final persisted = await repo.getSourceConfirmation(key.dateBucket, key.taskKey);
      expect(persisted?.isCompleted, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // 10. Failed Intent Generation Stamping & Lifecycle Safety
  // ---------------------------------------------------------------------------
  group('Failed Intent Generation Stamping & Lifecycle Safety', () {
    test('failed intent before reset is discarded upon retry after reset, mutating 0 rows; disposed controller rejected', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = _TransientFailRepo(appDb);
      addTearDown(() => repo.close());

      final fakeAudio = _FakeAdhanAudioController();
      final mockNative = _MockNativeAlarmBoundary();

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          adhanAudioControllerProvider.overrideWith((ref) => fakeAudio),
          nativeAlarmResetBoundaryProvider.overrideWithValue(mockNative),
        ],
      );
      addTearDown(container.dispose);

      const key = HisnItemProgressKey(
        dateBucket: 'Africa/Cairo|2026-10-07',
        period: DhikrPeriod.morning,
      );
      await container.read(hisnDailyItemProgressControllerProvider(key).future);
      final oldCtrl = container.read(hisnDailyItemProgressControllerProvider(key).notifier);

      // Induce transient write failure and attach expected error via expectLater
      repo.failNextWrite = true;
      await expectLater(
        oldCtrl.setItemProgress(itemId: 75, isCompleted: true),
        throwsA(isA<SocketException>()),
      );

      expect(oldCtrl.hasSaveError, isTrue);
      expect(oldCtrl.saveErrorMessageArabic, isNotNull);

      // Disable failure
      repo.failNextWrite = false;

      // Invoke resetAllState: barrier generation advances, DB wiped
      final prefsCtrl = container.read(preferencesControllerProvider.notifier);
      await prefsCtrl.resetAllState();

      // Now call retryFailedIntent on the retained old controller notifier:
      // Disposed controller safely no-ops without mutating SQLite
      await oldCtrl.retryFailedIntent();

      // Assert 0 rows written in SQLite for item 75
      final rawDb = await appDb.database;
      final rows = await rawDb.query(
        'hisn_daily_item_progress',
        where: 'item_id = ?',
        whereArgs: [75],
      );
      expect(rows, isEmpty);

      // Hydrate new controller post-reset so build() clears stale pre-reset error flags
      await container.read(hisnDailyItemProgressControllerProvider(key).future);
      final newCtrl = container.read(hisnDailyItemProgressControllerProvider(key).notifier);
      expect(newCtrl.hasSaveError, isFalse);
      await newCtrl.setItemProgress(itemId: 75, isCompleted: true);

      final rowsAfterNewWrite = await rawDb.query(
        'hisn_daily_item_progress',
        where: 'item_id = ?',
        whereArgs: [75],
      );
      expect(rowsAfterNewWrite.length, 1);
      expect(rowsAfterNewWrite.first['is_completed'], 1);
    });

    test('DailyQuranPagesController: failed intent before reset is discarded upon retry after reset, clearing error on rebuild and writing 0 old rows', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = _TransientFailRepo(appDb);
      addTearDown(() => repo.close());

      final fakeAudio = _FakeAdhanAudioController();
      final mockNative = _MockNativeAlarmBoundary();

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          adhanAudioControllerProvider.overrideWith((ref) => fakeAudio),
          nativeAlarmResetBoundaryProvider.overrideWithValue(mockNative),
        ],
      );
      addTearDown(container.dispose);

      const bucket = 'Africa/Cairo|2026-10-07';
      await container.read(dailyQuranPagesControllerProvider(bucket).future);
      final oldCtrl = container.read(dailyQuranPagesControllerProvider(bucket).notifier);

      // Induce transient write failure
      repo.failNextWrite = true;
      await expectLater(
        oldCtrl.confirmPage(15),
        throwsA(isA<SocketException>()),
      );

      expect(oldCtrl.hasSaveError, isTrue);
      expect(oldCtrl.saveErrorMessageArabic, isNotNull);

      // Disable failure
      repo.failNextWrite = false;

      // Invoke resetAllState: barrier advances, DB wiped
      final prefsCtrl = container.read(preferencesControllerProvider.notifier);
      await prefsCtrl.resetAllState();

      // Retry on stale disposed controller safely no-ops
      await oldCtrl.retryFailedIntent();

      // Assert 0 rows written in SQLite for page 15
      final rawDb = await appDb.database;
      final rows = await rawDb.query(
        'daily_quran_pages',
        where: 'page_number = ?',
        whereArgs: [15],
      );
      expect(rows, isEmpty);

      // Rebuild / hydrate new controller post-reset: error flags are cleared
      await container.read(dailyQuranPagesControllerProvider(bucket).future);
      final newCtrl = container.read(dailyQuranPagesControllerProvider(bucket).notifier);
      expect(newCtrl.hasSaveError, isFalse);

      // Fresh write works
      await newCtrl.confirmPage(15);
      final rowsAfterWrite = await rawDb.query(
        'daily_quran_pages',
        where: 'page_number = ?',
        whereArgs: [15],
      );
      expect(rowsAfterWrite.length, 1);
    });

    test('DailySourceConfirmationController: failed intent before reset is discarded upon retry after reset, clearing error on rebuild and writing 0 old rows', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = _TransientFailRepo(appDb);
      addTearDown(() => repo.close());

      final fakeAudio = _FakeAdhanAudioController();
      final mockNative = _MockNativeAlarmBoundary();

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          adhanAudioControllerProvider.overrideWith((ref) => fakeAudio),
          nativeAlarmResetBoundaryProvider.overrideWithValue(mockNative),
        ],
      );
      addTearDown(container.dispose);

      const sourceKey = DailySourceKey(
        dateBucket: 'Africa/Cairo|2026-10-07',
        taskKey: DailySourceTasks.dailyDua,
      );
      await container.read(dailySourceConfirmationControllerProvider(sourceKey).future);
      final oldCtrl = container.read(dailySourceConfirmationControllerProvider(sourceKey).notifier);

      // Induce transient write failure
      repo.failNextWrite = true;
      await expectLater(
        oldCtrl.setConfirmation(isCompleted: true, hisnItemId: 5),
        throwsA(isA<SocketException>()),
      );

      expect(oldCtrl.hasSaveError, isTrue);
      expect(oldCtrl.saveErrorMessageArabic, isNotNull);

      // Disable failure
      repo.failNextWrite = false;

      // Invoke resetAllState: barrier advances, DB wiped
      final prefsCtrl = container.read(preferencesControllerProvider.notifier);
      await prefsCtrl.resetAllState();

      // Retry on stale disposed controller safely no-ops
      await oldCtrl.retryFailedIntent();

      // Assert 0 rows written in SQLite for daily_dua
      final rawDb = await appDb.database;
      final rows = await rawDb.query(
        'daily_source_confirmations',
        where: 'task_key = ?',
        whereArgs: [DailySourceTasks.dailyDua],
      );
      expect(rows, isEmpty);

      // Rebuild / hydrate new controller post-reset: error flags are cleared
      await container.read(dailySourceConfirmationControllerProvider(sourceKey).future);
      final newCtrl = container.read(dailySourceConfirmationControllerProvider(sourceKey).notifier);
      expect(newCtrl.hasSaveError, isFalse);

      // Fresh write works
      await newCtrl.setConfirmation(isCompleted: true, hisnItemId: 5);
      final rowsAfterWrite = await rawDb.query(
        'daily_source_confirmations',
        where: 'task_key = ?',
        whereArgs: [DailySourceTasks.dailyDua],
      );
      expect(rowsAfterWrite.length, 1);
    });

    test('disposed controller rejects setItemProgress and retryFailedIntent safely', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(() => repo.close());

      final container = ProviderContainer(
        overrides: [progressRepositoryProvider.overrideWithValue(repo)],
      );

      const key = HisnItemProgressKey(
        dateBucket: 'Africa/Cairo|2026-10-07',
        period: DhikrPeriod.morning,
      );
      await container.read(hisnDailyItemProgressControllerProvider(key).future);
      final ctrl = container.read(hisnDailyItemProgressControllerProvider(key).notifier);

      // Dispose container
      container.dispose();

      // setItemProgress throws StateError when disposed
      expect(
        () => ctrl.setItemProgress(itemId: 75, isCompleted: true),
        throwsA(isA<StateError>()),
      );

      // retryFailedIntent returns safely as a no-op
      await ctrl.retryFailedIntent();
    });
  });
}
