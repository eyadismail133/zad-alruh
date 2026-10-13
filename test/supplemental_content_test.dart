import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/features/hisn/presentation/controllers/hisn_provider.dart';
import 'package:zad_alruh/src/features/hisn/presentation/hisn_detail_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/favorites_screen.dart';
import 'package:zad_alruh/src/features/progress/data/models/favorite.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';
import 'package:zad_alruh/src/features/hadith/presentation/controllers/hadith_provider.dart';
import 'package:zad_alruh/src/features/hadith/presentation/hadith_detail_screen.dart';
import 'package:zad_alruh/src/features/hisn/presentation/daily/daily_dua_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_alruh/src/features/hadith/data/hadith_repository_impl.dart';
import 'package:zad_alruh/src/features/hisn/data/hisn_repository_impl.dart';
import 'package:zad_alruh/src/features/hisn/data/supplemental_hisn_repository.dart';
import 'package:zad_alruh/src/features/hisn/domain/models/hisn_invocation_catalog.dart';
import 'package:zad_alruh/src/features/hisn/presentation/utils/hisn_text_formatter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'schema five upgrade preserves old confirmations and permits supplemental prayers',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'supplement_migration_',
      );
      final path = '${directory.path}/history.db';
      final old = await databaseFactoryFfiNoIsolate.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (database, _) async {
            await database.execute(
              'CREATE TABLE daily_source_confirmations (date_bucket TEXT NOT NULL, task_key TEXT NOT NULL, hisn_item_id INTEGER CHECK (hisn_item_id IS NULL OR (hisn_item_id >= 1 AND hisn_item_id <= 267)), is_completed INTEGER NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(date_bucket, task_key))',
            );
            await database.execute(
              'CREATE INDEX idx_daily_source_confirmations_bucket ON daily_source_confirmations (date_bucket)',
            );
            await database.insert('daily_source_confirmations', {
              'date_bucket': 'Africa/Cairo|2026-10-07',
              'task_key': 'daily_dua',
              'hisn_item_id': 1,
              'is_completed': 1,
              'updated_at': '2026-10-07T10:00:00',
            });
          },
        ),
      );
      await old.close();
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: path,
      );
      try {
        final progress = ProgressRepository(database);
        final legacy = await progress.getSourceConfirmation(
          'Africa/Cairo|2026-10-07',
          'daily_dua',
        );
        expect(legacy!.hisnItemId, 1);
        expect(legacy.isCompleted, isTrue);
        await progress.setSourceConfirmation(
          dateBucket: 'Africa/Cairo|2026-10-08',
          taskKey: 'daily_dua',
          isCompleted: true,
          hisnItemId: 1003057,
        );
        expect(
          (await progress.getSourceConfirmation(
            'Africa/Cairo|2026-10-08',
            'daily_dua',
          ))!.hisnItemId,
          1003057,
        );
      } finally {
        await database.close();
        directory.deleteSync(recursive: true);
      }
    },
  );
  testWidgets(
    'supplementary prayer can be selected and confirmed through the daily picker',
    (tester) async {
      final hisn = HisnRepositoryImpl.fromBytes(
        File('assets/content/hisn/hisn-muslim.json').readAsBytesSync(),
      );
      final hadiths = HadithRepositoryImpl.fromBytes(
        File('assets/content/hadith/hadith-enc-sahih.json').readAsBytesSync(),
      );
      final combined = SupplementalHisnRepository(hisn: hisn, hadiths: hadiths);
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      );
      final progress = ProgressRepository(database);
      await tester.runAsync(progress.getPreferences);
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(database),
              progressRepositoryProvider.overrideWithValue(progress),
              hisnRepositoryProvider.overrideWith((ref) async => combined),
            ],
            child: const MaterialApp(home: DailyDuaScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '3057');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('select_dua_1003057')), findsOneWidget);
        await tester.tap(find.byKey(const Key('select_dua_1003057')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('daily_dua_confirm_checkbox')),
        );
        await tester.tap(find.byKey(const Key('daily_dua_confirm_checkbox')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Checkbox>(
                find.byKey(const Key('daily_dua_confirm_checkbox')),
              )
              .value,
          isTrue,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(database.close);
      }
    },
  );

  testWidgets(
    'hadith favorites open ordered details and a single back returns to favorites',
    (tester) async {
      final hadiths = HadithRepositoryImpl.fromBytes(
        File('assets/content/hadith/hadith-enc-sahih.json').readAsBytesSync(),
      );
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      );
      final progress = ProgressRepository(database);
      await tester.runAsync(
        () => progress.addFavorite(
          const Favorite(
            contentKind: 'hadith',
            stableId: '1751',
            title: 'saved hadith',
          ),
        ),
      );
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              progressRepositoryProvider.overrideWithValue(progress),
              hadithRepositoryProvider.overrideWith((ref) async => hadiths),
            ],
            child: const MaterialApp(home: FavoritesScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('المفضلة'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('saved hadith'));
        await tester.pumpAndSettle();
        expect(find.byType(HadithDetailScreen), findsOneWidget);
        await tester.tap(find.byTooltip('الحديث التالي'));
        await tester.pumpAndSettle();
        expect(find.text('حديث #${hadiths.allHadiths[1].id}'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(FavoritesScreen), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(database.close);
      }
    },
  );
  testWidgets(
    'saved supplementary prayer opens its source and can be removed from favorites',
    (tester) async {
      final hisn = HisnRepositoryImpl.fromBytes(
        File('assets/content/hisn/hisn-muslim.json').readAsBytesSync(),
      );
      final hadiths = HadithRepositoryImpl.fromBytes(
        File('assets/content/hadith/hadith-enc-sahih.json').readAsBytesSync(),
      );
      final combined = SupplementalHisnRepository(hisn: hisn, hadiths: hadiths);
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      );
      final progress = ProgressRepository(database);
      final prayer = combined.getById(1003057)!;
      await tester.runAsync(
        () => progress.addFavorite(
          Favorite(
            contentKind: 'hisn',
            stableId: '${prayer.id}',
            title: prayer.chapterTitle,
          ),
        ),
      );
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              progressRepositoryProvider.overrideWithValue(progress),
              hisnRepositoryProvider.overrideWith((ref) async => combined),
            ],
            child: const MaterialApp(home: FavoritesScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('المفضلة'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(prayer.chapterTitle));
        await tester.pumpAndSettle();
        expect(find.byType(HisnDetailScreen), findsOneWidget);
        expect(find.text(prayer.text), findsOneWidget);
        await tester.tap(find.byTooltip('إزالة من المفضلة'));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () async => expect(await progress.getFavorites(), isEmpty),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(database.close);
      }
    },
  );
  test(
    'supplement adds distinct source entries while preserving canonical counts and attribution',
    () async {
      final hisn = HisnRepositoryImpl.fromBytes(
        File('assets/content/hisn/hisn-muslim.json').readAsBytesSync(),
      );
      final hadiths = HadithRepositoryImpl.fromBytes(
        File('assets/content/hadith/hadith-enc-sahih.json').readAsBytesSync(),
      );
      final combined = SupplementalHisnRepository(hisn: hisn, hadiths: hadiths);
      expect(combined.count, 267);
      expect(combined.chaptersCount, 132);
      expect(combined.supplementalItems.length, 24);
      expect(
        combined.supplementalItems.map((entry) => entry.id).toSet().length,
        24,
      );
      for (final entry in combined.supplementalItems) {
        final source = hadiths.getById(entry.sourceHadithId!)!;
        expect(entry.text, source.hadithText);
        expect(entry.number, source.id);
        expect(entry.footnotes.single.text, contains(source.takhrij));
        expect(entry.footnotes.single.text, contains(source.link));
        expect(combined.getById(entry.id), entry);
        final clipboard = HisnTextFormatter.formatForClipboard(entry);
        expect(clipboard, contains('HadeethEnc'));
        expect(clipboard, isNot(contains('القحطاني')));
      }
      final prayer = combined.getById(1003057)!;
      expect(HisnInvocationCatalog.contains(prayer.id), isTrue);
      expect(
        combined.search('الهدى').any((entry) => entry.id == prayer.id),
        isTrue,
      );
      expect(HisnInvocationCatalog.contains(1004201), isFalse);
    },
  );
}
