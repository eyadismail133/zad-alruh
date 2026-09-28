import 'dart:async';
import 'dart:io';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/features/progress/data/models/bookmark.dart';
import 'package:zad_alruh/src/features/progress/data/models/favorite.dart';
import 'package:zad_alruh/src/features/progress/data/models/reading_progress.dart';
import 'package:zad_alruh/src/features/progress/data/models/user_preferences.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';
import 'package:zad_alruh/src/features/quran/data/quran_repository.dart';
import 'package:zad_alruh/src/features/quran/data/sources/quran_asset_loader.dart';

void main() {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late QuranRepository quranRepo;

  setUpAll(() async {
    final textBytes = await File(
      'assets/content/quran/quran-uthmani.txt',
    ).readAsBytes();
    final xmlBytes = await File(
      'assets/content/quran/quran-data.xml',
    ).readAsBytes();
    quranRepo = QuranRepository.fromBytes(
      textBytes: textBytes,
      xmlBytes: xmlBytes,
    );
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zad_alruh_test_');
    dbPath = p.join(tempDir.path, 'zad_alruh_test.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ProgressRepository - Persistence & Reopen', () {
    test(
      'persists state after repository and database close and reopen',
      () async {
        final db1 = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo1 = ProgressRepository(
          db1,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo1.close());

        final initialReading = await repo1.getReadingProgress();
        expect(initialReading.lastPage, 1);
        expect(initialReading.selectedSurah, isNull);

        await repo1.saveReadingProgress(
          const ReadingProgress(
            lastPage: 12,
            selectedSurah: 2,
            selectedVerse: 77,
          ),
        );

        await repo1.savePreferences(
          const UserPreferences(
            darkMode: 'dark',
            textScale: 1.25,
            selectedCity: 'مكة المكرمة',
            selectedTimezone: 'Asia/Riyadh',
            quranDefaultGoal: 4,
            notificationsEnabled: false,
            activeDhikrSessionId: 'session_active_01',
          ),
        );

        await repo1.updateDailyTask(
          dateBucket: '2026-09-27',
          quranCompleted: true,
          morningDhikrCompleted: true,
          quranPagesRead: 4,
          quranGoalPages: 4,
        );

        final bookmarkId = await repo1.createBookmark(
          name: 'صفحة الحزب الأول',
          pageNumber: 12,
          surahNumber: 2,
          verseNumber: 77,
        );
        expect(bookmarkId, isPositive);

        await repo1.addFavorite(
          const Favorite(
            contentKind: 'hadith',
            stableId: 'hadith_001',
            title: 'إنما الأعمال بالنيات',
            subtitle: 'صحيح البخاري - حديث ١',
          ),
        );

        await repo1.close();

        // Reopen repository with the exact same database file
        final db2 = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo2 = ProgressRepository(
          db2,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo2.close());

        final reopenedReading = await repo2.getReadingProgress();
        expect(reopenedReading.lastPage, 12);
        expect(reopenedReading.selectedSurah, 2);
        expect(reopenedReading.selectedVerse, 77);

        final reopenedPrefs = await repo2.getPreferences();
        expect(reopenedPrefs.darkMode, 'dark');
        expect(reopenedPrefs.textScale, 1.25);
        expect(reopenedPrefs.selectedCity, 'مكة المكرمة');
        expect(reopenedPrefs.selectedTimezone, 'Asia/Riyadh');
        expect(reopenedPrefs.quranDefaultGoal, 4);
        expect(reopenedPrefs.activeDhikrSessionId, 'session_active_01');

        final dailyProgress = await repo2.getDailyProgress('2026-09-27');
        expect(dailyProgress.quranCompleted, isTrue);
        expect(dailyProgress.morningDhikrCompleted, isTrue);
        expect(dailyProgress.eveningDhikrCompleted, isFalse);
        expect(dailyProgress.quranPagesRead, 4);
        expect(dailyProgress.quranGoalPages, 4);
        expect(dailyProgress.completedTasksCount, 2);

        final bookmarks = await repo2.getBookmarks();
        expect(bookmarks.length, 1);
        expect(bookmarks.first.name, 'صفحة الحزب الأول');
        expect(bookmarks.first.pageNumber, 12);

        final isFav = await repo2.isFavorite('hadith', 'hadith_001');
        expect(isFav, isTrue);

        await repo2.close();
      },
    );
  });

  group('ProgressRepository - Bookmarks and Favorites Identity', () {
    test(
      'named CRUD bookmark operations enforce bounds and persist updates',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          db,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        expect(
          () => repo.createBookmark(name: 'Invalid Page', pageNumber: 0),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => repo.createBookmark(name: 'Invalid Page', pageNumber: 605),
          throwsA(isA<ArgumentError>()),
        );

        final id = await repo.createBookmark(
          name: 'علامة سورة البقرة',
          pageNumber: 2,
          surahNumber: 2,
          verseNumber: 1,
        );

        var list = await repo.getBookmarks();
        expect(list.length, 1);
        expect(list.first.id, id);
        expect(list.first.name, 'علامة سورة البقرة');
        expect(list.first.pageNumber, 2);

        await repo.updateBookmark(
          Bookmark(
            id: id,
            name: 'علامة الجزء الأول',
            pageNumber: 21,
            surahNumber: 2,
            verseNumber: 141,
            createdAt: list.first.createdAt,
          ),
        );

        list = await repo.getBookmarks();
        expect(list.length, 1);
        expect(list.first.name, 'علامة الجزء الأول');
        expect(list.first.pageNumber, 21);

        await repo.deleteBookmark(id);
        list = await repo.getBookmarks();
        expect(list.isEmpty, isTrue);

        await repo.close();
      },
    );

    test(
      'unique favorites constraint preserves identity and avoids duplicates',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        const fav1 = Favorite(
          contentKind: 'dua',
          stableId: 'dua_morning_01',
          title: 'أذكار الصباح',
        );

        await repo.addFavorite(fav1);
        expect(await repo.isFavorite('dua', 'dua_morning_01'), isTrue);

        const favDuplicate = Favorite(
          contentKind: 'dua',
          stableId: 'dua_morning_01',
          title: 'أذكار الصباح - محدث',
        );
        await repo.addFavorite(favDuplicate);

        final favorites = await repo.getFavoritesByKind('dua');
        expect(favorites.length, 1);
        expect(favorites.first.title, 'أذكار الصباح - محدث');

        const favHadith = Favorite(
          contentKind: 'hadith',
          stableId: 'dua_morning_01',
          title: 'حديث مستقل',
        );
        await repo.addFavorite(favHadith);

        final allFavs = await repo.getFavorites();
        expect(allFavs.length, 2);

        await repo.removeFavorite('dua', 'dua_morning_01');
        expect(await repo.isFavorite('dua', 'dua_morning_01'), isFalse);
        expect(await repo.isFavorite('hadith', 'dua_morning_01'), isTrue);

        await repo.close();
      },
    );
  });

  group('ProgressRepository - Dhikr Sessions & Atomic Increments', () {
    test(
      'capped atomic increments strictly enforce target bound under concurrency',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        final session = await repo.startDhikrSession(
          sessionId: 'session_subhanallah_01',
          dhikrId: 'subhan_allah',
          category: 'morning',
          targetCount: 33,
          dateBucket: '2026-09-27',
        );
        expect(session.currentCount, 0);
        expect(session.targetCount, 33);
        expect(session.isCompleted, isFalse);

        final futures = List.generate(
          50,
          (_) => repo.incrementDhikrSession('session_subhanallah_01'),
        );
        await Future.wait(futures);

        final updated = await repo.getDhikrSession('session_subhanallah_01');
        expect(updated, isNotNull);
        expect(updated!.currentCount, 33);
        expect(updated.isCompleted, isTrue);

        final extra = await repo.incrementDhikrSession(
          'session_subhanallah_01',
        );
        expect(extra.currentCount, 33);
        expect(extra.isCompleted, isTrue);

        await repo.close();
      },
    );

    test(
      'startDhikrSession rejects duplicate session IDs and never resets existing counter',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        await repo.startDhikrSession(
          sessionId: 'session_unique_101',
          dhikrId: 'tasbeeh',
          category: 'general',
          targetCount: 33,
          dateBucket: '2026-09-27',
        );

        // Increment 5 times
        for (int i = 0; i < 5; i++) {
          await repo.incrementDhikrSession('session_unique_101');
        }

        var current = await repo.getDhikrSession('session_unique_101');
        expect(current!.currentCount, 5);

        // Attempting to start with the same session ID must throw and NOT overwrite/reset
        await expectLater(
          repo.startDhikrSession(
            sessionId: 'session_unique_101',
            dhikrId: 'tasbeeh',
            category: 'general',
            targetCount: 33,
            dateBucket: '2026-09-27',
          ),
          throwsA(isA<StateError>()),
        );

        current = await repo.getDhikrSession('session_unique_101');
        expect(current!.currentCount, 5); // Count remains strictly 5

        await repo.close();
      },
    );

    test('exposes resumable unfinished historical dhikr sessions', () async {
      final db = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(db);
      addTearDown(() => repo.close());

      // Start session 1: completed
      await repo.startDhikrSession(
        sessionId: 'session_done',
        dhikrId: 'tasbeeh',
        category: 'general',
        targetCount: 3,
        dateBucket: '2026-09-25',
      );
      for (int i = 0; i < 3; i++) {
        await repo.incrementDhikrSession('session_done');
      }

      // Start session 2: unfinished
      await repo.startDhikrSession(
        sessionId: 'session_unfin_1',
        dhikrId: 'tasbeeh',
        category: 'general',
        targetCount: 33,
        dateBucket: '2026-09-26',
      );
      await repo.incrementDhikrSession('session_unfin_1');

      // Start session 3: unfinished
      await repo.startDhikrSession(
        sessionId: 'session_unfin_2',
        dhikrId: 'hamd',
        category: 'general',
        targetCount: 100,
        dateBucket: '2026-09-27',
      );

      final unfinished = await repo.getUnfinishedDhikrSessions();
      expect(unfinished.length, 2);
      expect(
        unfinished.map((s) => s.sessionId),
        containsAll(['session_unfin_1', 'session_unfin_2']),
      );
      expect(
        unfinished.map((s) => s.sessionId),
        isNot(contains('session_done')),
      );

      await repo.close();
    });
  });

  group('ProgressRepository - Daily Progress Goal Initialization (Finding 9)', () {
    test(
      'first daily task write initializes goal from stored preferences (stored default 8)',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        // Set stored default goal to 8 in preferences
        final initialPrefs = await repo.getPreferences();
        await repo.savePreferences(initialPrefs.copyWith(quranDefaultGoal: 8));

        // Perform first daily task write for a new date bucket without providing explicit goal
        final daily = await repo.updateDailyTask(
          dateBucket: '2026-09-27',
          dailyDuaCompleted: true,
        );

        // Must be initialized from stored preference (8), NOT hardcoded 2!
        expect(daily.quranGoalPages, 8);
        expect(daily.dailyDuaCompleted, isTrue);

        await repo.close();
      },
    );
  });

  group('ProgressRepository - Timezone & Clock Rollover (Finding 3)', () {
    test(
      'computes date bucket correctly across device/selected timezone discrepancy and midnight',
      () {
        ensureTimeZonesInitialized();

        // Device time: 2026-09-26 22:30:00 UTC
        final utcTime = DateTime.utc(2026, 9, 26, 22, 30);

        // In UTC, it's 2026-09-26
        expect(computeDateBucket(utcTime, 'UTC'), 'UTC|2026-09-26');

        // In Riyadh (UTC+3), 22:30 UTC is 01:30 on 2026-09-27
        expect(
          computeDateBucket(utcTime, 'Asia/Riyadh'),
          'Asia/Riyadh|2026-09-27',
        );

        // In Cairo (UTC+3), it's 01:30 on 2026-09-27
        expect(
          computeDateBucket(utcTime, 'Africa/Cairo'),
          'Africa/Cairo|2026-09-27',
        );

        // Midnight rollover: 23:59:50 vs 00:00:10
        final beforeMidnight = DateTime.utc(
          2026,
          9,
          26,
          20,
          59,
          50,
        ); // 23:59:50 in Cairo
        final afterMidnight = DateTime.utc(
          2026,
          9,
          26,
          21,
          0,
          10,
        ); // 00:00:10 in Cairo

        expect(
          computeDateBucket(beforeMidnight, 'Africa/Cairo'),
          'Africa/Cairo|2026-09-26',
        );
        expect(
          computeDateBucket(afterMidnight, 'Africa/Cairo'),
          'Africa/Cairo|2026-09-27',
        );

        // Separate formatting helpers from storage key
        expect(formatDisplayDate('Africa/Cairo|2026-09-27'), '2026-09-27');
        expect(formatDisplayDate('2026-09-27'), '2026-09-27');
        expect(
          parseTimezoneFromBucket('Africa/Cairo|2026-09-27'),
          'Africa/Cairo',
        );
        expect(parseTimezoneFromBucket('2026-09-27'), '');
      },
    );

    test(
      'throws explicit ArgumentError for invalid IANA timezone instead of silent device fallback',
      () {
        ensureTimeZonesInitialized();
        expect(
          () => computeDateBucket(DateTime.now(), 'Mars/Base_Alpha'),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test(
      'activeDateBucketNotifier automatically rolls over at midnight via actual timer in fakeAsync',
      () {
        ensureTimeZonesInitialized();
        fakeAsync((FakeAsync async) {
          // Start 10 seconds before midnight Cairo time (23:59:50 Cairo = 20:59:50 UTC)
          DateTime simulatedNow = DateTime.utc(2026, 9, 26, 20, 59, 50);
          final container = ProviderContainer(
            overrides: [clockProvider.overrideWithValue(() => simulatedNow)],
          );

          final initialBucket = container.read(activeDateBucketProvider);
          expect(initialBucket, 'Africa/Cairo|2026-09-26');

          // Advance simulated time past midnight (15 seconds forward)
          simulatedNow = simulatedNow.add(const Duration(seconds: 15));
          // Elapse fake time by 15 seconds to fire the internal _midnightTimer
          async.elapse(const Duration(seconds: 15));

          // Provider must have rolled over to day 2 automatically without manual refresh()
          final rolledOverBucket = container.read(activeDateBucketProvider);
          expect(rolledOverBucket, 'Africa/Cairo|2026-09-27');

          container.dispose();
        });
      },
    );

    test(
      'already-loaded activeDateBucketProvider switches timezone on same calendar date, writes distinct progress, and preserves history on switch back',
      () async {
        ensureTimeZonesInitialized();
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        // Fixed point in time: 12:00 PM UTC on 2026-09-27
        final fixedTime = DateTime.utc(2026, 9, 27, 12, 0);
        final container = ProviderContainer(
          overrides: [
            progressRepositoryProvider.overrideWithValue(repo),
            clockProvider.overrideWithValue(() => fixedTime),
          ],
        );
        addTearDown(container.dispose);

        // 1. Initial active bucket is Cairo for 2026-09-27
        await container.read(preferencesControllerProvider.future);
        final cairoBucket = container.read(activeDateBucketProvider);
        expect(cairoBucket, 'Africa/Cairo|2026-09-27');

        // 2. Complete Quran task in Cairo bucket
        await container
            .read(dailyProgressControllerProvider(cairoBucket).notifier)
            .toggleTask(quranCompleted: true);
        final cairoProgress1 = await container.read(
          dailyProgressControllerProvider(cairoBucket).future,
        );
        expect(cairoProgress1.quranCompleted, isTrue);
        expect(cairoProgress1.dailyDuaCompleted, isFalse);

        // 3. Switch city & timezone to Riyadh via preferencesControllerProvider
        final currentPrefs = await container.read(
          preferencesControllerProvider.future,
        );
        await container
            .read(preferencesControllerProvider.notifier)
            .updatePreferences(
              currentPrefs.copyWith(
                selectedCity: 'الرياض',
                selectedTimezone: 'Asia/Riyadh',
              ),
            );

        // 4. activeDateBucketProvider automatically updates to Riyadh on same calendar date
        final riyadhBucket = container.read(activeDateBucketProvider);
        expect(riyadhBucket, 'Asia/Riyadh|2026-09-27');

        // 5. Riyadh bucket has distinct fresh progress (not yet completed)
        final riyadhProgress1 = await container.read(
          dailyProgressControllerProvider(riyadhBucket).future,
        );
        expect(riyadhProgress1.quranCompleted, isFalse);

        // 6. Complete Dua task in Riyadh bucket
        await container
            .read(dailyProgressControllerProvider(riyadhBucket).notifier)
            .toggleTask(dailyDuaCompleted: true);
        final riyadhProgress2 = await container.read(
          dailyProgressControllerProvider(riyadhBucket).future,
        );
        expect(riyadhProgress2.dailyDuaCompleted, isTrue);
        expect(riyadhProgress2.quranCompleted, isFalse);

        // 7. Switch back to Cairo
        await container
            .read(preferencesControllerProvider.notifier)
            .updatePreferences(
              currentPrefs.copyWith(
                selectedCity: 'القاهرة',
                selectedTimezone: 'Africa/Cairo',
              ),
            );

        final returnedCairoBucket = container.read(activeDateBucketProvider);
        expect(returnedCairoBucket, 'Africa/Cairo|2026-09-27');

        // 8. Verify original Cairo progress was preserved intact
        final cairoProgressPreserved = await container.read(
          dailyProgressControllerProvider(cairoBucket).future,
        );
        expect(cairoProgressPreserved.quranCompleted, isTrue);
        expect(cairoProgressPreserved.dailyDuaCompleted, isFalse);

        // 9. Verify Riyadh progress also remains intact
        final riyadhProgressPreserved = await container.read(
          dailyProgressControllerProvider(riyadhBucket).future,
        );
        expect(riyadhProgressPreserved.dailyDuaCompleted, isTrue);
        expect(riyadhProgressPreserved.quranCompleted, isFalse);

        container.dispose();
        await repo.close();
      },
    );

    test(
      'legacy bare-date records preserve history when queried with timezone-qualified bucket',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        // Insert legacy record with bare date '2026-09-27'
        await repo.updateDailyTask(
          dateBucket: '2026-09-27',
          quranCompleted: true,
          dailyDuaCompleted: true,
        );

        // Query using timezone-qualified bucket 'Africa/Cairo|2026-09-27'
        final qualifiedProgress = await repo.getDailyProgress(
          'Africa/Cairo|2026-09-27',
        );
        expect(qualifiedProgress.quranCompleted, isTrue);
        expect(qualifiedProgress.dailyDuaCompleted, isTrue);

        // Updating via qualified key updates the same legacy record
        await repo.updateDailyTask(
          dateBucket: 'Africa/Cairo|2026-09-27',
          morningDhikrCompleted: true,
        );

        final updated = await repo.getDailyProgress('Africa/Cairo|2026-09-27');
        expect(updated.morningDhikrCompleted, isTrue);
        expect(updated.quranCompleted, isTrue);

        await repo.close();
      },
    );
  });

  group(
    'ProgressRepository - Real Closed/Read-Only DB Failure & Reset (Finding 4, 5)',
    () {
      test(
        'real SQLite read-only failure throws SQLITE_READONLY and recovers on query_only OFF',
        () async {
          final db = AppDatabase(
            databaseFactory: databaseFactory,
            databasePath: dbPath,
          );
          final repo = ProgressRepository(db);
          addTearDown(() => repo.close());

          final rawDb = await db.database;

          // Enable SQLite read-only pragma
          await rawDb.execute('PRAGMA query_only = ON;');

          // Attempting mutation must fail with read-only database error
          await expectLater(
            repo.createBookmark(name: 'علامة تجريبية', pageNumber: 10),
            throwsA(anything),
          );

          // Recover database to read-write mode
          await rawDb.execute('PRAGMA query_only = OFF;');

          // Retry mutation: must succeed
          final bookmarkId = await repo.createBookmark(
            name: 'علامة تجريبية',
            pageNumber: 10,
          );
          expect(bookmarkId, isPositive);

          final bookmarks = await repo.getBookmarks();
          expect(bookmarks.length, 1);
          expect(bookmarks.first.name, 'علامة تجريبية');
          expect(bookmarks.first.pageNumber, 10);

          await repo.close();
        },
      );

      test(
        'atomic session start sets active session and persists across database reopen',
        () async {
          final db1 = AppDatabase(
            databaseFactory: databaseFactory,
            databasePath: dbPath,
          );
          final repo1 = ProgressRepository(db1);
          addTearDown(() => repo1.close());

          // Start session with atomic active selection
          final session = await repo1.startDhikrSession(
            sessionId: 'session_atomic_persist',
            dhikrId: 'istighfar',
            category: 'general',
            targetCount: 100,
            dateBucket: '2026-09-27',
            setActive: true,
          );
          expect(session.sessionId, 'session_atomic_persist');

          final prefs1 = await repo1.getPreferences();
          expect(prefs1.activeDhikrSessionId, 'session_atomic_persist');

          // Duplicate session ID rejection does not alter existing session
          await expectLater(
            repo1.startDhikrSession(
              sessionId: 'session_atomic_persist',
              dhikrId: 'istighfar',
              category: 'general',
              targetCount: 100,
              dateBucket: '2026-09-27',
            ),
            throwsA(isA<StateError>()),
          );

          // Close database
          await repo1.close();

          // Reopen repository with same path
          final db2 = AppDatabase(
            databaseFactory: databaseFactory,
            databasePath: dbPath,
          );
          final repo2 = ProgressRepository(db2);
          addTearDown(() => repo2.close());

          final prefs2 = await repo2.getPreferences();
          expect(prefs2.activeDhikrSessionId, 'session_atomic_persist');

          final reopenedSession = await repo2.getDhikrSession(
            'session_atomic_persist',
          );
          expect(reopenedSession, isNotNull);
          expect(reopenedSession!.targetCount, 100);

          await repo2.close();
        },
      );

      test(
        'meaningful failing mutation on closed DB throws recoverable exception',
        () async {
          final db = AppDatabase(
            databaseFactory: databaseFactory,
            databasePath: dbPath,
          );
          final repo = ProgressRepository(db);
          addTearDown(() => repo.close());

          // Close the database to simulate connection or IO failure
          await repo.close();

          // Mutation on closed DB must throw and not hang or silently drop
          await expectLater(
            repo.createBookmark(name: 'علامة', pageNumber: 5),
            throwsA(anything),
          );

          await expectLater(repo.resetLocalState(), throwsA(anything));
        },
      );

      test(
        'resetLocalState clears all tables and invalidates loaded Riverpod providers',
        () async {
          final db = AppDatabase(
            databaseFactory: databaseFactory,
            databasePath: dbPath,
          );
          final repo = ProgressRepository(
            db,
            versePageValidator: quranRepo.isValidVerseOnPage,
          );
          addTearDown(() => repo.close());

          // Populate data
          await repo.saveReadingProgress(
            const ReadingProgress(
              lastPage: 155,
              selectedSurah: 7,
              selectedVerse: 40,
            ),
          );
          await repo.savePreferences(
            const UserPreferences(
              darkMode: 'dark',
              textScale: 1.4,
              selectedCity: 'الرياض',
              selectedTimezone: 'Asia/Riyadh',
              quranDefaultGoal: 5,
              notificationsEnabled: true,
              activeDhikrSessionId: 'session_xyz',
            ),
          );
          await repo.createBookmark(name: 'علامة', pageNumber: 155);
          await repo.addFavorite(
            const Favorite(contentKind: 'dua', stableId: 'd1', title: 'دعاء'),
          );
          await repo.startDhikrSession(
            sessionId: 'session_xyz',
            dhikrId: 'd1',
            category: 'morning',
            targetCount: 33,
            dateBucket: '2026-09-27',
          );
          await repo.updateDailyTask(
            dateBucket: '2026-09-27',
            quranCompleted: true,
          );

          // Test with Riverpod container
          final container = ProviderContainer(
            overrides: [
              quranRepositoryProvider.overrideWith(
                (ref) => Future.value(quranRepo),
              ),
              progressRepositoryProvider.overrideWithValue(repo),
            ],
          );
          addTearDown(container.dispose);

          // Pre-load providers into memory
          await container.read(readingProgressControllerProvider.future);
          await container.read(bookmarksControllerProvider.future);
          await container.read(favoritesControllerProvider.future);
          await container.read(
            dailyProgressControllerProvider('2026-09-27').future,
          );
          await container.read(
            dhikrSessionsControllerProvider('2026-09-27').future,
          );
          await container.read(unfinishedDhikrSessionsProvider.future);

          // Perform reset via controller
          await container
              .read(preferencesControllerProvider.notifier)
              .resetAllState();

          // Verify reloaded providers reflect reset state
          final freshReading = await container.read(
            readingProgressControllerProvider.future,
          );
          expect(freshReading.lastPage, 1);

          final freshBookmarks = await container.read(
            bookmarksControllerProvider.future,
          );
          expect(freshBookmarks, isEmpty);

          final freshFavs = await container.read(
            favoritesControllerProvider.future,
          );
          expect(freshFavs, isEmpty);

          final freshDaily = await container.read(
            dailyProgressControllerProvider('2026-09-27').future,
          );
          expect(freshDaily.completedTasksCount, 0);

          final freshSessions = await container.read(
            dhikrSessionsControllerProvider('2026-09-27').future,
          );
          expect(freshSessions, isEmpty);

          final freshPrefs = await container.read(
            preferencesControllerProvider.future,
          );
          expect(freshPrefs.darkMode, 'system');
          expect(freshPrefs.activeDhikrSessionId, isNull);

          container.dispose();
          await repo.close();
        },
      );

      test(
        'UserPreferences copyWith supports clearing activeDhikrSessionId to null',
        () {
          const prefs = UserPreferences(
            darkMode: 'dark',
            textScale: 1.5,
            selectedCity: 'مكة',
            selectedTimezone: 'Asia/Riyadh',
            quranDefaultGoal: 4,
            notificationsEnabled: true,
            activeDhikrSessionId: 'session_active_abc',
          );

          // Explicit null clears activeDhikrSessionId
          final clearedByNull = prefs.copyWith(activeDhikrSessionId: null);
          expect(clearedByNull.activeDhikrSessionId, isNull);
          expect(clearedByNull.selectedCity, 'مكة');
          expect(clearedByNull.darkMode, 'dark');
          expect(clearedByNull.quranDefaultGoal, 4);

          // clearActiveDhikrSession flag clears activeDhikrSessionId
          final clearedByFlag = prefs.copyWith(clearActiveDhikrSession: true);
          expect(clearedByFlag.activeDhikrSessionId, isNull);
          expect(clearedByFlag.selectedCity, 'مكة');

          // Omission retains existing activeDhikrSessionId
          final retained = prefs.copyWith(darkMode: 'light');
          expect(retained.activeDhikrSessionId, 'session_active_abc');
          expect(retained.darkMode, 'light');
        },
      );

      test(
        'clearing active dhikr session through controller preserves unrelated preferences across reopen',
        () async {
          final db1 = AppDatabase(
            databaseFactory: databaseFactory,
            databasePath: dbPath,
          );
          final repo1 = ProgressRepository(db1);
          addTearDown(() => repo1.close());

          // 1. Seed custom preferences with active session ID
          await repo1.savePreferences(
            const UserPreferences(
              darkMode: 'dark',
              textScale: 1.25,
              selectedCity: 'الرياض',
              selectedTimezone: 'Asia/Riyadh',
              quranDefaultGoal: 5,
              notificationsEnabled: false,
              activeDhikrSessionId: 'session_active_123',
            ),
          );

          final container = ProviderContainer(
            overrides: [progressRepositoryProvider.overrideWithValue(repo1)],
          );
          addTearDown(container.dispose);

          // Verify seeded preferences loaded
          final initialPrefs = await container.read(
            preferencesControllerProvider.future,
          );
          expect(initialPrefs.activeDhikrSessionId, 'session_active_123');
          expect(initialPrefs.selectedCity, 'الرياض');
          expect(initialPrefs.quranDefaultGoal, 5);

          // 2. Clear active session through controller
          await container
              .read(preferencesControllerProvider.notifier)
              .setActiveDhikrSessionId(null);

          // Verify active session cleared in container
          final updatedPrefs = await container.read(
            preferencesControllerProvider.future,
          );
          expect(updatedPrefs.activeDhikrSessionId, isNull);
          expect(updatedPrefs.selectedCity, 'الرياض');
          expect(updatedPrefs.selectedTimezone, 'Asia/Riyadh');
          expect(updatedPrefs.quranDefaultGoal, 5);
          expect(updatedPrefs.darkMode, 'dark');

          container.dispose();
          await repo1.close();

          // 3. Reopen repository from disk and assert persistence
          final db2 = AppDatabase(
            databaseFactory: databaseFactory,
            databasePath: dbPath,
          );
          final repo2 = ProgressRepository(db2);
          addTearDown(() => repo2.close());

          final persistedPrefs = await repo2.getPreferences();
          expect(persistedPrefs.activeDhikrSessionId, isNull);
          expect(persistedPrefs.selectedCity, 'الرياض');
          expect(persistedPrefs.selectedTimezone, 'Asia/Riyadh');
          expect(persistedPrefs.quranDefaultGoal, 5);
          expect(persistedPrefs.darkMode, 'dark');
          expect(persistedPrefs.textScale, 1.25);

          await repo2.close();
        },
      );
    },
  );

  group('ProgressRepository - Verse Page Validation and Identity Stability', () {
    test(
      'rejects explicit verse writes when validator is unavailable',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db); // No validator provided
        addTearDown(() => repo.close());

        // Explicit verse save must throw StateError
        await expectLater(
          repo.saveReadingProgress(
            const ReadingProgress(
              lastPage: 3,
              selectedSurah: 2,
              selectedVerse: 12,
            ),
          ),
          throwsA(isA<StateError>()),
        );

        // Bookmark with explicit verse must throw StateError
        await expectLater(
          repo.createBookmark(
            name: 'علامة',
            pageNumber: 3,
            surahNumber: 2,
            verseNumber: 12,
          ),
          throwsA(isA<StateError>()),
        );

        // Page-only save succeeds even without validator
        await repo.saveReadingProgress(const ReadingProgress(lastPage: 10));
        final reading = await repo.getReadingProgress();
        expect(reading.lastPage, 10);
        expect(reading.selectedSurah, isNull);
        expect(reading.selectedVerse, isNull);

        // Page-only bookmark succeeds even without validator
        final bId = await repo.createBookmark(
          name: 'علامة صفحة فقط',
          pageNumber: 10,
        );
        expect(bId, isPositive);

        // Unrelated preferences and counters remain fully usable
        await repo.savePreferences(const UserPreferences(darkMode: 'dark'));
        final prefs = await repo.getPreferences();
        expect(prefs.darkMode, 'dark');

        await repo.close();
      },
    );

    test(
      'rejects mismatched verse-page mapping and unpaired nullables with validator',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          db,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        // Verse 2:12 is on page 3, NOT page 12
        await expectLater(
          repo.saveReadingProgress(
            const ReadingProgress(
              lastPage: 12,
              selectedSurah: 2,
              selectedVerse: 12,
            ),
          ),
          throwsA(isA<ArgumentError>()),
        );

        // Unpaired nullables in reading progress
        await expectLater(
          repo.saveReadingProgress(
            const ReadingProgress(
              lastPage: 3,
              selectedSurah: 2,
              selectedVerse: null,
            ),
          ),
          throwsA(isA<ArgumentError>()),
        );

        // Bookmark with mismatched verse-page
        await expectLater(
          repo.createBookmark(
            name: 'باطل',
            pageNumber: 12,
            surahNumber: 2,
            verseNumber: 12,
          ),
          throwsA(isA<ArgumentError>()),
        );

        // Bookmark with unpaired nullables
        await expectLater(
          repo.createBookmark(
            name: 'باطل',
            pageNumber: 3,
            surahNumber: 2,
            verseNumber: null,
          ),
          throwsA(isA<ArgumentError>()),
        );

        await repo.close();
      },
    );

    test(
      'progressRepositoryProvider identity remains stable when quranRepository loads',
      () async {
        final container = ProviderContainer(
          overrides: [
            quranRepositoryProvider.overrideWith(
              (ref) => Future.value(quranRepo),
            ),
          ],
        );
        addTearDown(container.dispose);

        final repoBefore = container.read(progressRepositoryProvider);
        // Wait for Quran future to resolve
        final qRepo = await container.read(quranRepositoryProvider.future);
        expect(qRepo, isNotNull);

        final repoAfter = container.read(progressRepositoryProvider);
        // Identity must be identical - ProgressRepository was not recreated
        expect(identical(repoBefore, repoAfter), isTrue);
      },
    );
  });

  group('ReadingProgressController - Validation and Contracts', () {
    test('rejects invalid page range < 1 or > 604', () async {
      final db = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(
        db,
        versePageValidator: quranRepo.isValidVerseOnPage,
      );
      addTearDown(() => repo.close());

      final container = ProviderContainer(
        overrides: [
          quranRepositoryProvider.overrideWith(
            (ref) => Future.value(quranRepo),
          ),
          progressRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(
        readingProgressControllerProvider.notifier,
      );
      await container.read(readingProgressControllerProvider.future);

      expect(() => controller.savePage(0), throwsArgumentError);
      expect(() => controller.savePage(605), throwsArgumentError);
      expect(() => controller.savePageNavigation(0), throwsArgumentError);
      expect(() => controller.savePageNavigation(605), throwsArgumentError);
    });

    test('rejects paired nullable mismatch in savePage', () async {
      final db = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(
        db,
        versePageValidator: quranRepo.isValidVerseOnPage,
      );
      addTearDown(() => repo.close());

      final container = ProviderContainer(
        overrides: [
          quranRepositoryProvider.overrideWith(
            (ref) => Future.value(quranRepo),
          ),
          progressRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(
        readingProgressControllerProvider.notifier,
      );
      await container.read(readingProgressControllerProvider.future);

      expect(
        () => controller.savePage(2, surah: 2, verse: null),
        throwsArgumentError,
      );
      expect(
        () => controller.savePage(2, surah: null, verse: 1),
        throwsArgumentError,
      );
    });

    test(
      'savePage clears stop verse while savePageNavigation preserves same-page verse',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          db,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        // Seed progress at page 12 with stop verse 2:77
        await repo.saveReadingProgress(
          const ReadingProgress(
            lastPage: 12,
            selectedSurah: 2,
            selectedVerse: 77,
          ),
        );

        final container = ProviderContainer(
          overrides: [
            quranRepositoryProvider.overrideWith(
              (ref) => Future.value(quranRepo),
            ),
            progressRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(
          readingProgressControllerProvider.notifier,
        );
        await container.read(readingProgressControllerProvider.future);

        // savePageNavigation to same page 12 preserves verse
        await controller.savePageNavigation(12);
        final navProgress = await repo.getReadingProgress();
        expect(navProgress.lastPage, 12);
        expect(navProgress.selectedSurah, 2);
        expect(navProgress.selectedVerse, 77);

        // savePage alone clears stop verse
        await controller.savePage(12);
        final clearedProgress = await repo.getReadingProgress();
        expect(clearedProgress.lastPage, 12);
        expect(clearedProgress.selectedSurah, isNull);
        expect(clearedProgress.selectedVerse, isNull);
      },
    );

    test(
      'reset during blocked write cancels pre-reset save, rejects concurrent nav, and resets SQLite and provider to default page 1 across reopen',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          db,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        final container = ProviderContainer(
          overrides: [
            quranRepositoryProvider.overrideWith(
              (ref) => Future.value(quranRepo),
            ),
            progressRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(
          readingProgressControllerProvider.notifier,
        );
        final preferencesController = container.read(
          preferencesControllerProvider.notifier,
        );
        await container.read(readingProgressControllerProvider.future);

        final rawDb = await db.database;
        final lockCompleter = Completer<void>();
        final insideTxCompleter = Completer<void>();

        final txFuture = rawDb.transaction((txn) async {
          insideTxCompleter.complete();
          await lockCompleter.future;
        });
        await insideTxCompleter.future;

        try {
          // 1. Enqueue nav2 while DB lock is held, with expectation attached immediately
          final nav2Expectation = expectLater(
            controller.savePageNavigation(2),
            throwsA(isA<StateError>()),
          );

          // 2. Enqueue reset
          final resetFuture = preferencesController.resetAllState();

          // 3. Enqueue nav3 with expectation attached immediately
          final nav3Expectation = expectLater(
            controller.savePageNavigation(3),
            throwsA(isA<StateError>()),
          );

          // 4. Release SQLite lock and await reset and cancelled expectations
          lockCompleter.complete();
          await txFuture;

          await resetFuture;
          await nav2Expectation;
          await nav3Expectation;

          // 5. Assert SQLite and provider reflect reset defaults (page 1, surah/verse null)
          final sqliteProgress = await repo.getReadingProgress();
          expect(sqliteProgress.lastPage, 1);
          expect(sqliteProgress.selectedSurah, isNull);
          expect(sqliteProgress.selectedVerse, isNull);

          final providerProgress = container
              .read(readingProgressControllerProvider)
              .valueOrNull;
          expect(providerProgress?.lastPage, 1);
          expect(providerProgress?.selectedSurah, isNull);
          expect(providerProgress?.selectedVerse, isNull);

          // 6. Reopen fresh repo and provider from disk: must still be page 1
          container.dispose();
          await repo.close();

          final dbReopen = AppDatabase(
            databaseFactory: databaseFactory,
            databasePath: dbPath,
          );
          final repoReopen = ProgressRepository(
            dbReopen,
            versePageValidator: quranRepo.isValidVerseOnPage,
          );
          addTearDown(() => repoReopen.close());

          final containerReopen = ProviderContainer(
            overrides: [
              quranRepositoryProvider.overrideWith(
                (ref) => Future.value(quranRepo),
              ),
              progressRepositoryProvider.overrideWithValue(repoReopen),
            ],
          );
          addTearDown(containerReopen.dispose);

          final freshReading = await containerReopen.read(
            readingProgressControllerProvider.future,
          );
          expect(freshReading.lastPage, 1);
          expect(freshReading.selectedSurah, isNull);
          expect(freshReading.selectedVerse, isNull);
        } finally {
          if (!lockCompleter.isCompleted) {
            lockCompleter.complete();
          }
          await txFuture;
        }
      },
    );

    test(
      'bootstrap failure retains accepted nav destination then retry genuinely persists',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          db,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        final rawDb = await db.database;
        // Make DB read-only before bootstrap so initial insert in getReadingProgress fails
        await rawDb.execute('PRAGMA query_only = ON;');

        final container = ProviderContainer(
          overrides: [
            quranRepositoryProvider.overrideWith(
              (ref) => Future.value(quranRepo),
            ),
            progressRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(
          readingProgressControllerProvider.notifier,
        );

        // Attempting navigation while DB cannot bootstrap fails with SQLite error
        final navFuture = controller.savePageNavigation(5);
        await expectLater(navFuture, throwsA(anything));
        expect(controller.hasSaveError, isTrue);

        // Recover database to read-write
        await rawDb.execute('PRAGMA query_only = OFF;');

        // retrySave genuinely retries the retained destination (page 5) and persists it
        await controller.retrySave();
        expect(controller.hasSaveError, isFalse);

        final persisted = await repo.getReadingProgress();
        expect(persisted.lastPage, 5);

        final inMemory = container
            .read(readingProgressControllerProvider)
            .valueOrNull;
        expect(inMemory?.lastPage, 5);
      },
    );

    test(
      'blocked save2 / nav3 / retry finishes 3 without regressing to stale page',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          db,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        final container = ProviderContainer(
          overrides: [
            quranRepositoryProvider.overrideWith(
              (ref) => Future.value(quranRepo),
            ),
            progressRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(
          readingProgressControllerProvider.notifier,
        );
        await container.read(readingProgressControllerProvider.future);

        final rawDb = await db.database;
        final lockCompleter = Completer<void>();
        final insideTxCompleter = Completer<void>();

        final txFuture = rawDb.transaction((txn) async {
          insideTxCompleter.complete();
          await lockCompleter.future;
        });
        await insideTxCompleter.future;

        Future<void>? save2Future;
        Future<void>? nav3Future;
        Future<void>? retryFuture;

        try {
          save2Future = controller.savePageNavigation(2);
          nav3Future = controller.savePageNavigation(3);

          // Drive event loop until older execution adopts target 2 at blocked persistence
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (controller.latestIntended?.lastPage != 2) {
            if (DateTime.now().isAfter(deadline)) {
              fail(
                'Timed out waiting for older execution to reach blocked persistence at page 2',
              );
            }
            await Future<void>.delayed(Duration.zero);
          }

          retryFuture = controller.retrySave();

          lockCompleter.complete();
          await txFuture;

          await save2Future;
          await nav3Future;
          await retryFuture;

          final persisted = await repo.getReadingProgress();
          expect(persisted.lastPage, 3);

          final inMemory = container
              .read(readingProgressControllerProvider)
              .valueOrNull;
          expect(inMemory?.lastPage, 3);
        } finally {
          if (!lockCompleter.isCompleted) {
            lockCompleter.complete();
          }
          await txFuture;
          if (save2Future != null) {
            try {
              await save2Future;
            } catch (_) {}
          }
          if (nav3Future != null) {
            try {
              await nav3Future;
            } catch (_) {}
          }
          if (retryFuture != null) {
            try {
              await retryFuture;
            } catch (_) {}
          }
          await controller.drainPendingWrites();
        }
      },
    );

    test(
      'blocked exact stop then new navigation then retry clears stale verse',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          db,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        final container = ProviderContainer(
          overrides: [
            quranRepositoryProvider.overrideWith(
              (ref) => Future.value(quranRepo),
            ),
            progressRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(
          readingProgressControllerProvider.notifier,
        );
        await container.read(readingProgressControllerProvider.future);

        final rawDb = await db.database;
        final lockCompleter = Completer<void>();
        final insideTxCompleter = Completer<void>();

        final txFuture = rawDb.transaction((txn) async {
          insideTxCompleter.complete();
          await lockCompleter.future;
        });
        await insideTxCompleter.future;

        Future<void>? retryFuture;
        final exactStopFuture = controller.saveExactStopVerse(
          page: 2,
          surah: 2,
          verse: 1,
        );
        final nav3Future = controller.savePageNavigation(3);

        try {
          // Drive event loop until older execution adopts target 2 at blocked persistence
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (controller.latestIntended?.lastPage != 2) {
            if (DateTime.now().isAfter(deadline)) {
              fail(
                'Timed out waiting for older execution to reach blocked persistence at page 2',
              );
            }
            await Future<void>.delayed(Duration.zero);
          }

          // Retry save while exact stop is blocked in persistence
          retryFuture = controller.retrySave();

          // Release lock and settle queue
          lockCompleter.complete();
          await txFuture;

          await exactStopFuture;
          await nav3Future;
          await retryFuture;

          // Assert page 3 is persisted and stale verse from page 2 was cleared
          final persisted = await repo.getReadingProgress();
          expect(persisted.lastPage, 3);
          expect(persisted.selectedSurah, isNull);
          expect(persisted.selectedVerse, isNull);

          final inMemory = container
              .read(readingProgressControllerProvider)
              .valueOrNull;
          expect(inMemory?.lastPage, 3);
          expect(inMemory?.selectedSurah, isNull);
          expect(inMemory?.selectedVerse, isNull);
        } finally {
          if (!lockCompleter.isCompleted) {
            lockCompleter.complete();
          }
          await txFuture;
          try {
            await exactStopFuture;
          } catch (_) {}
          try {
            await nav3Future;
          } catch (_) {}
          if (retryFuture != null) {
            try {
              await retryFuture;
            } catch (_) {}
          }
          await controller.drainPendingWrites();
        }
      },
    );

    test(
      'invalid exact ref then valid same-page nav preserves last VALID state',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          db,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        // Seed with valid progress: page 2, surah 2, verse 1 (Al-Baqarah 1 is on page 2)
        await repo.saveReadingProgress(
          const ReadingProgress(
            lastPage: 2,
            selectedSurah: 2,
            selectedVerse: 1,
          ),
        );

        final container = ProviderContainer(
          overrides: [
            quranRepositoryProvider.overrideWith(
              (ref) => Future.value(quranRepo),
            ),
            progressRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(
          readingProgressControllerProvider.notifier,
        );
        await container.read(readingProgressControllerProvider.future);

        // Invalid exact stop: Surah 1 verse 5 (Al-Fatihah 5) is on page 1, NOT page 2
        await expectLater(
          controller.saveExactStopVerse(page: 2, surah: 1, verse: 5),
          throwsA(isA<ArgumentError>()),
        );

        // Same-page navigation to page 2: must preserve last VALID stop verse (2:1), NOT poisoned
        await controller.savePageNavigation(2);

        final persisted = await repo.getReadingProgress();
        expect(persisted.lastPage, 2);
        expect(persisted.selectedSurah, 2);
        expect(persisted.selectedVerse, 1);

        final inMemory = container
            .read(readingProgressControllerProvider)
            .valueOrNull;
        expect(inMemory?.lastPage, 2);
        expect(inMemory?.selectedSurah, 2);
        expect(inMemory?.selectedVerse, 1);
      },
    );

    test(
      'immediate retry after exact stop retains newly selected verse under writer lock',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          db,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        final container = ProviderContainer(
          overrides: [
            quranRepositoryProvider.overrideWith(
              (ref) => Future.value(quranRepo),
            ),
            progressRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        await repo.saveReadingProgress(const ReadingProgress(lastPage: 1));
        await container.read(readingProgressControllerProvider.future);
        final controller = container.read(
          readingProgressControllerProvider.notifier,
        );

        final rawDb = await db.database;
        final entered = Completer<void>();
        final release = Completer<void>();
        Future<void>? transaction;
        final operations = <Future<void>>[];

        try {
          transaction = rawDb.transaction((txn) async {
            entered.complete();
            await release.future;
          });
          await entered.future;

          operations.add(controller.clearStopVerse(2));
          operations.add(
            controller.saveExactStopVerse(page: 2, surah: 2, verse: 1),
          );
          operations.add(controller.retrySave());

          release.complete();
          await transaction;
          await Future.wait(operations);

          final saved = await repo.getReadingProgress();
          expect(saved.lastPage, 2);
          expect(
            saved.selectedSurah,
            2,
            reason: 'Immediate retry must preserve validated newer exact stop',
          );
          expect(saved.selectedVerse, 1);

          final inMemory = container
              .read(readingProgressControllerProvider)
              .valueOrNull;
          expect(inMemory?.lastPage, 2);
          expect(inMemory?.selectedSurah, 2);
          expect(inMemory?.selectedVerse, 1);
        } finally {
          if (!release.isCompleted) release.complete();
          if (transaction != null) {
            try {
              await transaction;
            } catch (_) {}
          }
          await Future.wait(
            operations.map((f) => f.catchError((Object _, StackTrace __) {})),
          );
          await controller.drainPendingWrites();
        }
      },
    );
  });
}
