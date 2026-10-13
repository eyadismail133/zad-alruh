import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/main.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/features/hadith/data/hadith_repository_impl.dart';
import 'package:zad_alruh/src/features/hadith/presentation/controllers/hadith_provider.dart';
import 'package:zad_alruh/src/features/prayer/data/sources/city_asset_adapter.dart';
import 'package:zad_alruh/src/features/prayer/domain/repositories/city_repository.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  ensureTimeZonesInitialized();
  late CityRepository cities;
  late HadithRepositoryImpl hadiths;

  setUpAll(() async {
    cities = CityAssetAdapter.fromBytes(
      await File('assets/content/cities/cities15000.txt').readAsBytes(),
    );
    hadiths = HadithRepositoryImpl.fromBytes(
      await File('assets/content/hadith/hadith-enc-sahih.json').readAsBytes(),
    );
    final font = FontLoader('Noto Naskh Arabic')
      ..addFont(
        File(
          'assets/fonts/NotoNaskhArabic-Variable.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await font.load();
  });

  for (final scale in [1.0, 1.8]) {
    testWidgets(
      'bottom hadith tab opens the list and preserves existing tabs at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repository = ProgressRepository(
          AppDatabase(
            databaseFactory: databaseFactoryFfiNoIsolate,
            databasePath: inMemoryDatabasePath,
          ),
        );
        addTearDown(repository.close);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
        await tester.runAsync(() async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                progressRepositoryProvider.overrideWithValue(repository),
                cityRepositoryProvider.overrideWith((ref) async => cities),
                hadithRepositoryProvider.overrideWith((ref) async => hadiths),
              ],
              child: const ZadAlruhApp(),
            ),
          );
          final container = ProviderScope.containerOf(
            tester.element(find.byType(ZadAlruhApp)),
          );
          await container.read(preferencesControllerProvider.future);
          await container.read(cityRepositoryProvider.future);
        });
        await _pumpFrames(tester);

        Finder tab(String label) => find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        );
        expect(tab('الحديث').hitTestable(), findsOneWidget);
        final navigationBounds = tester.getRect(find.byType(NavigationBar));
        for (final label in [
          'الرئيسية',
          'القرآن',
          'الصلاة',
          'الأذكار',
          'المزيد',
          'الحديث',
        ]) {
          final paragraph = tester.renderObject<RenderParagraph>(tab(label));
          expect(paragraph.didExceedMaxLines, isFalse, reason: label);
          expect(
            paragraph.getMaxIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(paragraph.size.width + 0.01),
            reason: '$label must remain readable on one line',
          );
          final labelBounds = tester.getRect(tab(label));
          expect(navigationBounds.contains(labelBounds.topLeft), isTrue);
          expect(navigationBounds.contains(labelBounds.bottomRight), isTrue);
        }
        await tester.tap(tab('الحديث'));
        await _pumpFrames(tester);
        expect(find.text('الأحاديث النبوية الشريفة'), findsOneWidget);
        expect(find.text(hadiths.allHadiths.first.title), findsOneWidget);
        expect(find.byType(BackButton), findsNothing);
        expect(tester.takeException(), isNull);

        for (final destination in {
          'المزيد': 'الإعدادات',
          'الصلاة': 'مواقيت الصلاة',
          'القرآن': 'القرآن الكريم',
          'الأذكار': 'التسبيح والذكر',
          'الرئيسية': 'وِردك اليومي',
        }.entries) {
          await tester.tap(tab(destination.key));
          await _pumpFrames(tester);
          expect(find.text(destination.value), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
