// Renders real app screens to PNG for the landing page.
// Run: flutter test screenshot_test --update-goldens
// Output: screenshot_test/out/*.png (not part of the normal test suite).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/main.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/theme/app_theme.dart';
import 'package:zad_alruh/src/features/more/presentation/settings_screen.dart';
import 'package:zad_alruh/src/features/prayer/data/sources/city_asset_adapter.dart';
import 'package:zad_alruh/src/features/prayer/domain/repositories/city_repository.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';
import 'package:zad_alruh/src/features/quran/presentation/controllers/quran_navigation_controller.dart';
import 'package:zad_alruh/src/features/quran/presentation/widgets/mushaf_paper.dart';
import 'package:zad_alruh/src/features/reminders/presentation/reminders_screen.dart';

const Size kPhone = Size(390, 844);

void main() {
  sqfliteFfiInit();
  ensureTimeZonesInitialized();
  late CityRepository cityRepo;

  setUpAll(() async {
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
    final fonts = <String, List<String>>{
      'Noto Naskh Arabic': ['assets/fonts/NotoNaskhArabic-Variable.ttf'],
      AppTheme.uiFont: [
        'assets/fonts/IBM-Plex-Sans-Arabic-Regular.ttf',
        'assets/fonts/IBM-Plex-Sans-Arabic-Medium.ttf',
        'assets/fonts/IBM-Plex-Sans-Arabic-SemiBold.ttf',
        'assets/fonts/IBM-Plex-Sans-Arabic-Bold.ttf',
      ],
      'Amiri Quran': ['assets/fonts/Amiri-Quran-Regular.ttf'],
      'MaterialIcons': [
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    };
    for (final entry in fonts.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        final bytes = await File(path).readAsBytes();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
    cityRepo = CityAssetAdapter.fromBytes(
      File('assets/content/cities/cities15000.txt').readAsBytesSync(),
    );
  });

  Future<ProviderContainer> boot(WidgetTester tester) async {
    tester.view.physicalSize = kPhone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = ProgressRepository(
      AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      ),
    );
    addTearDown(repo.close);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
          ],
          child: const ZadAlruhApp(),
        ),
      );
      final c = ProviderScope.containerOf(
        tester.element(find.byType(ZadAlruhApp)),
      );
      await c.read(preferencesControllerProvider.future);
      await c.read(cityRepositoryProvider.future);
    });
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(ZadAlruhApp)));
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester);
    await expectLater(
      find.byType(ZadAlruhApp),
      matchesGoldenFile('out/$name.png'),
    );
  }

  Future<void> tapIcon(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon).first);
    await settle(tester);
  }

  testWidgets('home', (tester) async {
    await boot(tester);
    await shoot(tester, 'home');
  });

  testWidgets('home dark', (tester) async {
    final c = await boot(tester);
    await tester.runAsync(
      () => c.read(preferencesControllerProvider.notifier).setDarkMode('dark'),
    );
    await shoot(tester, 'home_dark');
  });

  for (final mode in [MushafPaperMode.sepia, MushafPaperMode.night]) {
    testWidgets('mushaf ${mode.name}', (tester) async {
      final c = await boot(tester);
      c.read(mushafPaperModeProvider.notifier).set(mode);
      c.read(quranNavigationProvider.notifier).openReader(3);
      await tapIcon(tester, Icons.menu_book_outlined);
      await tester.runAsync(() async {
        final ctx = tester.element(find.byType(Scaffold).last);
        await precacheImage(
          const AssetImage('assets/content/quran/pages/003.webp'),
          ctx,
        );
      });
      await shoot(tester, 'mushaf_${mode.name}');
    });
  }

  testWidgets('prayers', (tester) async {
    await boot(tester);
    await tapIcon(tester, Icons.mosque_outlined);
    await shoot(tester, 'prayers');
  });

  testWidgets('adhkar', (tester) async {
    await boot(tester);
    await tapIcon(tester, Icons.auto_awesome_outlined);
    await shoot(tester, 'adhkar');
  });

  testWidgets('quran index', (tester) async {
    await boot(tester);
    await tapIcon(tester, Icons.menu_book_outlined);
    await shoot(tester, 'quran_index');
  });

  testWidgets('settings', (tester) async {
    await boot(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await shoot(tester, 'settings');
  });

  testWidgets('reminders', (tester) async {
    await boot(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const RemindersScreen()));
    await shoot(tester, 'reminders');
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
  }
}
