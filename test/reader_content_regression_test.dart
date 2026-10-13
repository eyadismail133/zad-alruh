import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/features/hadith/data/hadith_repository_impl.dart';
import 'package:zad_alruh/src/features/hadith/domain/models/hadith_item.dart';
import 'package:zad_alruh/src/features/hadith/presentation/controllers/hadith_provider.dart';
import 'package:zad_alruh/src/features/hadith/presentation/hadith_detail_screen.dart';
import 'package:zad_alruh/src/features/hisn/data/hisn_repository_impl.dart';
import 'package:zad_alruh/src/features/more/presentation/duas_screen.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late HadithRepositoryImpl hadiths;
  late HisnRepositoryImpl hisn;
  setUpAll(() async {
    hadiths = HadithRepositoryImpl.fromBytes(
      await File('assets/content/hadith/hadith-enc-sahih.json').readAsBytes(),
    );
    hisn = HisnRepositoryImpl.fromBytes(
      await File('assets/content/hisn/hisn-muslim.json').readAsBytes(),
    );
  });

  test('source IDs sort numerically in browsing and search', () {
    final shuffled = HadithRepositoryImpl(
      metadata: hadiths.metadata,
      allHadiths: hadiths.allHadiths.reversed.toList(),
    );
    final sorted = hadiths.allHadiths.map((h) => h.id).toList()..sort();
    expect(shuffled.allHadiths.map((h) => h.id), sorted);
    final matches = shuffled.search('الله').map((h) => h.id).toList();
    expect(matches, matches.toList()..sort());
    final numericMatches = HadithRepositoryImpl(
      metadata: hadiths.metadata,
      allHadiths: [
        hadiths.getById(65004)!,
        HadithItem.fromJson({
          ...hadiths.allHadiths.first.toJson(),
          'title': '65004',
        }),
      ],
    );
    expect(numericMatches.search('65004').map((entry) => entry.id), [
      1751,
      65004,
    ]);
    expect(
      sorted.any(
        (id) => id.toString().length != sorted.first.toString().length,
      ),
      isTrue,
    );
  });

  testWidgets(
    'duas browsing excludes praise-only entries even in a dua chapter',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: DuasScreen(repository: hisn)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('الأدعية'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '122');
      await tester.pumpAndSettle();
      expect(find.text('ذكر #122'), findsNothing);
      await tester.enterText(find.byType(TextField), '120');
      await tester.pumpAndSettle();
      expect(find.text('دعاء #120'), findsOneWidget);
    },
  );

  test(
    'daily selection rejects praise while retaining legacy persisted history',
    () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      );
      final progress = ProgressRepository(database);
      addTearDown(database.close);
      final sqlite = await database.database;
      await sqlite.insert('daily_source_confirmations', {
        'date_bucket': 'Africa/Cairo|2026-10-07',
        'task_key': 'daily_dua',
        'hisn_item_id': 1,
        'is_completed': 1,
        'updated_at': DateTime.now().toIso8601String(),
      });
      for (final completed in [false, true]) {
        for (final disallowedId in [122, 1004201]) {
          await expectLater(
            progress.setSourceConfirmation(
              dateBucket: 'Africa/Cairo|2026-10-08',
              taskKey: 'daily_dua',
              isCompleted: completed,
              hisnItemId: disallowedId,
            ),
            throwsArgumentError,
          );
        }
      }
      expect(
        (await progress.getSourceConfirmation(
          'Africa/Cairo|2026-10-07',
          'daily_dua',
        ))!.hisnItemId,
        1,
      );
      await progress.setSourceConfirmation(
        dateBucket: 'Africa/Cairo|2026-10-08',
        taskKey: 'daily_dua',
        isCompleted: true,
        hisnItemId: 120,
      );
      await progress.setSourceConfirmation(
        dateBucket: 'Africa/Cairo|2026-10-09',
        taskKey: 'daily_dua',
        isCompleted: true,
        hisnItemId: 1003057,
      );
      expect(
        (await progress.getSourceConfirmation(
          'Africa/Cairo|2026-10-09',
          'daily_dua',
        ))!.hisnItemId,
        1003057,
      );
    },
  );

  testWidgets(
    'detail navigation resolves direct entries, disables boundaries and retains one route',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hadithRepositoryProvider.overrideWith((ref) async => hadiths),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        HadithDetailScreen(hadith: hadiths.allHadiths.first),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'الحديث السابق',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'الحديث التالي',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('حديث #${hadiths.allHadiths[1].id}'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hadithRepositoryProvider.overrideWith((ref) async => hadiths),
          ],
          child: MaterialApp(
            home: HadithDetailScreen(hadith: hadiths.allHadiths.last),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'الحديث التالي',
              ),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
