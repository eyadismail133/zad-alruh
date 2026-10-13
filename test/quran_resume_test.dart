import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/features/progress/data/models/reading_progress.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';
import 'package:zad_alruh/src/features/quran/data/quran_repository.dart';
import 'package:zad_alruh/src/features/quran/data/sources/quran_asset_loader.dart';

/// Gates delivery of a real SQLite snapshot while later writes remain available.
class _CapturedReadingRepository extends ProgressRepository {
  _CapturedReadingRepository(super.database, {super.versePageValidator});
  bool captureNext = false;
  final captured = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ReadingProgress> getReadingProgress() async {
    final snapshot = await super.getReadingProgress();
    if (captureNext) {
      captureNext = false;
      captured.complete();
      await release.future;
    }
    return snapshot;
  }
}

void main() {
  sqfliteFfiInit();
  test(
    'delayed resume refresh cannot replace later navigation or resurrect its cleared exact stop',
    () async {
      final quran = QuranRepository.fromBytes(
        textBytes: await File(
          'assets/content/quran/quran-uthmani.txt',
        ).readAsBytes(),
        xmlBytes: await File(
          'assets/content/quran/quran-data.xml',
        ).readAsBytes(),
      );
      final directory = await Directory.systemTemp.createTemp(
        'quran_refresh_race_',
      );
      final repository = _CapturedReadingRepository(
        AppDatabase(
          databaseFactory: databaseFactoryFfiNoIsolate,
          databasePath: '${directory.path}/test.db',
        ),
        versePageValidator: quran.isValidVerseOnPage,
      );
      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repository),
          quranRepositoryProvider.overrideWith((ref) => quran),
        ],
      );
      addTearDown(() async {
        if (!repository.release.isCompleted) repository.release.complete();
        container.dispose();
        await repository.close();
        await directory.delete(recursive: true);
      });
      await container.read(readingProgressControllerProvider.future);
      final controller = container.read(
        readingProgressControllerProvider.notifier,
      );
      await controller.saveExactStopVerse(page: 2, surah: 2, verse: 2);
      repository.captureNext = true;
      final refresh = controller.reloadPersistedResume();
      await repository.captured.future;
      await controller.savePageNavigation(3);
      repository.release.complete();
      await refresh;
      expect(controller.latestIntended!.lastPage, 3);
      expect(
        container.read(readingProgressControllerProvider).requireValue.lastPage,
        3,
      );
      await controller.savePageNavigation(2);
      expect((await repository.getReadingProgress()).selectedVerse, isNull);
    },
  );
  test(
    'v4 migration preserves exact stops and bookmark identity with legacy resume fallback',
    () async {
      final directory = await Directory.systemTemp.createTemp('quran_v4_');
      final path = '${directory.path}/test.db';
      final legacy = await databaseFactoryFfiNoIsolate.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE reading_progress (id INTEGER PRIMARY KEY, last_page INTEGER NOT NULL, selected_surah INTEGER, selected_verse INTEGER, updated_at TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE bookmarks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, page_number INTEGER NOT NULL, surah_number INTEGER, verse_number INTEGER, created_at TEXT NOT NULL)',
            );
            await db.execute(
              "CREATE TABLE daily_source_confirmations (date_bucket TEXT NOT NULL, task_key TEXT NOT NULL, hisn_item_id INTEGER CHECK (hisn_item_id IS NULL OR (hisn_item_id >= 1 AND hisn_item_id <= 267)), is_completed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, PRIMARY KEY(date_bucket, task_key))",
            );
            await db.insert('reading_progress', {
              'id': 1,
              'last_page': 2,
              'selected_surah': 2,
              'selected_verse': 2,
              'updated_at': '2026-10-09T00:00:00',
            });
            await db.insert('bookmarks', {
              'id': 81,
              'name': 'علامتي',
              'page_number': 2,
              'surah_number': 2,
              'verse_number': 2,
              'created_at': '2026-10-09T00:00:00',
            });
          },
        ),
      );
      await legacy.close();
      final db = AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: path,
      );
      final repo = ProgressRepository(db);
      addTearDown(() async {
        await repo.close();
        await directory.delete(recursive: true);
      });
      final progress = await repo.getReadingProgress();
      expect(progress.resumePage, 2);
      expect(progress.selectedSurah, 2);
      expect(progress.selectedVerse, 2);
      expect((await repo.getBookmarks()).single.id, 81);
      expect(await (await db.database).getVersion(), AppDatabase.schemaVersion);
    },
  );

  test(
    'failed resume update rolls back confirmation and retry persists both',
    () async {
      final directory = await Directory.systemTemp.createTemp('quran_atomic_');
      final db = AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: '${directory.path}/test.db',
      );
      final repo = ProgressRepository(db);
      addTearDown(() async {
        await repo.close();
        await directory.delete(recursive: true);
      });
      await repo.saveReadingProgress(const ReadingProgress(lastPage: 5));
      final database = await db.database;
      await database.execute(
        "CREATE TRIGGER reject_resume BEFORE UPDATE OF resume_page ON reading_progress BEGIN SELECT RAISE(ABORT, 'simulated resume failure'); END",
      );
      await expectLater(
        repo.confirmQuranPage(
          dateBucket: 'Africa/Cairo|2026-10-09',
          pageNumber: 5,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        await repo.getConfirmedQuranPages('Africa/Cairo|2026-10-09'),
        isEmpty,
      );
      expect((await repo.getReadingProgress()).resumePage, 5);
      await database.execute('DROP TRIGGER reject_resume');
      await repo.confirmQuranPage(
        dateBucket: 'Africa/Cairo|2026-10-09',
        pageNumber: 5,
      );
      expect(await repo.getConfirmedQuranPages('Africa/Cairo|2026-10-09'), {5});
      expect((await repo.getReadingProgress()).resumePage, 6);
    },
  );
  test(
    'confirmed next resume and exact stop survive database close and reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp('quran_reopen_');
      final path = '${directory.path}/test.db';
      final original = ProgressRepository(
        AppDatabase(
          databaseFactory: databaseFactoryFfiNoIsolate,
          databasePath: path,
        ),
        versePageValidator:
            ({
              required pageNumber,
              required surahNumber,
              required verseNumber,
            }) => pageNumber == 2 && surahNumber == 2 && verseNumber == 2,
      );
      await original.saveReadingProgress(
        const ReadingProgress(lastPage: 2, selectedSurah: 2, selectedVerse: 2),
      );
      await original.confirmQuranPage(
        dateBucket: 'Africa/Cairo|2026-10-09',
        pageNumber: 2,
      );
      await original.close();
      final reopened = ProgressRepository(
        AppDatabase(
          databaseFactory: databaseFactoryFfiNoIsolate,
          databasePath: path,
        ),
      );
      addTearDown(() async {
        await reopened.close();
        await directory.delete(recursive: true);
      });
      final progress = await reopened.getReadingProgress();
      expect(progress.resumePage, 3);
      expect(progress.lastPage, 2);
      expect(progress.selectedSurah, 2);
      expect(progress.selectedVerse, 2);
      expect(await reopened.getConfirmedQuranPages('Africa/Cairo|2026-10-09'), {
        2,
      });
    },
  );
  test(
    'confirmation atomically saves next resume page while preserving exact stop; undo and duplicate do not advance',
    () async {
      final directory = await Directory.systemTemp.createTemp('quran_resume_');
      final db = AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: '${directory.path}/test.db',
      );
      final repo = ProgressRepository(
        db,
        versePageValidator:
            ({
              required pageNumber,
              required surahNumber,
              required verseNumber,
            }) => true,
      );
      addTearDown(() async {
        await repo.close();
        await directory.delete(recursive: true);
      });
      await repo.saveReadingProgress(
        const ReadingProgress(lastPage: 2, selectedSurah: 2, selectedVerse: 2),
      );
      await repo.confirmQuranPage(
        dateBucket: 'Africa/Cairo|2026-10-09',
        pageNumber: 2,
      );
      final database = await db.database;
      var row = (await database.query('reading_progress')).single;
      expect(row['resume_page'], 3);
      expect(row['last_page'], 2);
      expect(row['selected_verse'], 2);
      await repo.confirmQuranPage(
        dateBucket: 'Africa/Cairo|2026-10-09',
        pageNumber: 2,
      );
      expect(await repo.getConfirmedQuranPages('Africa/Cairo|2026-10-09'), {2});
      await repo.undoQuranPage(
        dateBucket: 'Africa/Cairo|2026-10-09',
        pageNumber: 2,
      );
      row = (await database.query('reading_progress')).single;
      expect(row['resume_page'], 3);
      await repo.saveReadingProgress(const ReadingProgress(lastPage: 604));
      await repo.confirmQuranPage(
        dateBucket: 'Africa/Cairo|2026-10-09',
        pageNumber: 604,
      );
      expect(
        (await database.query('reading_progress')).single['resume_page'],
        604,
      );
      expect(await repo.getConfirmedQuranPages('Africa/Cairo|2026-10-09'), {
        604,
      });
    },
  );
}
