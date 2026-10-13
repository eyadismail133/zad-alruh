import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/theme/app_theme.dart';
import 'package:zad_alruh/src/core/widgets/retryable_error_view.dart';
import 'package:zad_alruh/src/features/dhikr/presentation/dhikr_screen.dart';
import 'package:zad_alruh/src/features/hisn/data/hisn_repository_impl.dart';
import 'package:zad_alruh/src/features/hisn/domain/repositories/hisn_repository.dart';
import 'package:zad_alruh/src/features/hisn/presentation/controllers/hisn_provider.dart';
import 'package:zad_alruh/src/features/hisn/presentation/daily/daily_hisn_checklist_screen.dart';
import 'package:zad_alruh/src/features/hisn/presentation/daily/post_prayer_daily_screen.dart';
import 'package:zad_alruh/src/features/hisn/presentation/hisn_chapter_screen.dart';
import 'package:zad_alruh/src/features/hisn/presentation/hisn_detail_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/duas_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/sources_screen.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';

class _TestAssetBundle extends Fake implements AssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async => '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Uint8List realJsonBytes;
  late HisnRepository realRepository;
  late AppDatabase testDb;
  late ProgressRepository testProgressRepo;

  setUpAll(() async {
    final notoBytes = await File('assets/fonts/NotoNaskhArabic-Variable.ttf').readAsBytes();
    final notoLoader = FontLoader('Noto Naskh Arabic');
    notoLoader.addFont(Future.value(ByteData.sublistView(notoBytes)));
    await notoLoader.load();

    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'D:/tools/flutter';
    final iconFile = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    ByteData iconData;
    if (iconFile.existsSync()) {
      final bytes = await iconFile.readAsBytes();
      expect(bytes.isNotEmpty, isTrue, reason: 'MaterialIcons font file must not be empty');
      iconData = ByteData.sublistView(bytes);
    } else {
      iconData = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
      expect(iconData.lengthInBytes, greaterThan(0), reason: 'MaterialIcons rootBundle font data must not be empty');
    }
    final fontLoaderIcons = FontLoader('MaterialIcons')
      ..addFont(Future.value(iconData));
    await fontLoaderIcons.load();

    final file = File('assets/content/hisn/hisn-muslim.json');
    expect(await file.exists(), isTrue, reason: 'Hisn JSON asset must exist');
    realJsonBytes = await file.readAsBytes();
    realRepository = HisnRepositoryImpl.fromBytes(realJsonBytes);
  });

  setUp(() {
    testDb = AppDatabase(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    testProgressRepo = ProgressRepository(testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  Widget buildTestApp({
    required Widget child,
    List<Override> overrides = const [],
    MediaQueryData? mediaQuery,
  }) {
    Widget content = MaterialApp(
      theme: AppTheme.lightTheme,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );
    if (mediaQuery != null) {
      content = MediaQuery(
        data: mediaQuery,
        child: content,
      );
    }
    return ProviderScope(
      overrides: [
        hisnRepositoryProvider.overrideWith((ref) => realRepository),
        progressRepositoryProvider.overrideWithValue(testProgressRepo),
        ...overrides,
      ],
      child: content,
    );
  }

  group('DuasScreen Widget Tests', () {
    testWidgets('renders chapters list with 132 chapters by default', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: const DuasScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('الأدعية والأذكار (حصن المسلم)'), findsOneWidget);
      expect(find.text('الأبواب والفصول (132)'), findsOneWidget);
      expect(find.text('جميع الأذكار (267)'), findsOneWidget);

      // Verify earliest chapter title is present
      expect(find.text('أَذْكَارُ الاسْـــتِيقَاظِ مِنَ النَّـــومِ'), findsOneWidget);
    });

    testWidgets('switches to all items list tab and displays items', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: const DuasScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap tab 2 (جميع الأذكار)
      await tester.tap(find.text('جميع الأذكار (267)'));
      await tester.pumpAndSettle();

      // Item 1 must be visible
      expect(find.text('ذكر #1'), findsOneWidget);
      expect(find.textContaining('الْحَمْدُ للَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا'), findsOneWidget);
    });

    testWidgets('search filters items and shows results count', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: const DuasScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter search query
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'الاستخارة');
      await tester.pumpAndSettle();

      // Expect search results count
      expect(find.text('نتائج البحث في حصن المسلم'), findsOneWidget);
      expect(find.textContaining('الاسْتِــــخَارَةِ'), findsWidgets);
      expect(find.textContaining('دعاء #74'), findsWidgets);

      // Clear search
      final clearButton = find.byTooltip('مسح البحث');
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      expect(find.text('الأبواب والفصول (132)'), findsOneWidget);
    });

    testWidgets('tapping chapter opens HisnChapterScreen', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: const DuasScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Chapter 1
      await tester.tap(find.text('أَذْكَارُ الاسْـــتِيقَاظِ مِنَ النَّـــومِ'));
      await tester.pumpAndSettle();

      expect(find.byType(HisnChapterScreen), findsOneWidget);
      expect(find.textContaining('الباب'), findsWidgets);
      expect(find.textContaining('أذكار'), findsWidgets);
      expect(find.textContaining('ذكر #'), findsWidgets);
    });

    testWidgets('tapping item in all items opens HisnDetailScreen with footnotes and attribution', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: const DuasScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to All Items
      await tester.tap(find.text('جميع الأذكار (267)'));
      await tester.pumpAndSettle();

      // Tap Item 1 card
      await tester.tap(find.text('ذكر #1'));
      await tester.pumpAndSettle();

      expect(find.byType(HisnDetailScreen), findsOneWidget);
      expect(find.text('ذكر #1'), findsOneWidget);
      expect(find.textContaining('الْحَمْدُ للَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا'), findsOneWidget);
      expect(find.textContaining('التخريج وهوامش المصدر'), findsOneWidget);
      expect(find.textContaining('المصدر والأمانة العلمية'), findsOneWidget);
      expect(find.textContaining('د. سعيد بن علي بن وهف القحطاني'), findsOneWidget);
      expect(find.textContaining('دار إسلام هاوس'), findsOneWidget);
    });

    testWidgets('HisnChapterScreen copy button copies text with author, source, and IslamHouse URL', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
        log.add(methodCall);
        return null;
      });

      final chapter = realRepository.getChapter(1)!;
      final firstItem = realRepository.getItemsByChapter(1).first;

      await tester.pumpWidget(
        buildTestApp(
          child: Scaffold(
            body: HisnChapterScreen(
              chapter: chapter,
              repository: realRepository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap copy button on first item
      final copyBtn = find.byTooltip('نسخ الذكر والمراجع').first;
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(find.text('تم نسخ نص الذكر والمراجع بنجاح'), findsOneWidget);

      final setClipboardCall = log.firstWhere((call) => call.method == 'Clipboard.setData');
      final text = (setClipboardCall.arguments as Map)['text'] as String;

      // Strengthened: directly verifies full original item.text + EACH original footnote + author + IslamHouse URL
      expect(text, contains(firstItem.text.trim()));
      for (final p in firstItem.paragraphs) {
        expect(text, contains(p.trim()));
      }
      for (final fn in firstItem.footnotes) {
        expect(text, contains(fn.text.trim()));
      }
      expect(text, contains(realRepository.metadata.author));
      expect(text, contains('دار إسلام هاوس'));
      expect(text, contains('https://islamhouse.com/ar/books/2522'));
    });

    testWidgets('HisnDetailScreen copy button copies text with author, source, and IslamHouse URL', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
        log.add(methodCall);
        return null;
      });

      // Use Item 75 (evening preface + 2 paragraphs + footnote 101)
      final item75 = realRepository.getById(75)!;

      await tester.pumpWidget(
        buildTestApp(
          child: HisnDetailScreen(item: item75),
        ),
      );
      await tester.pumpAndSettle();

      final copyBtn = find.byTooltip('نسخ نص الذكر والمراجع');
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(find.text('تم نسخ نص الذكر والمراجع بنجاح'), findsOneWidget);

      final setClipboardCall = log.firstWhere((call) => call.method == 'Clipboard.setData');
      final text = (setClipboardCall.arguments as Map)['text'] as String;

      // Strengthened: directly verifies full original item.text + EACH original footnote + author + IslamHouse URL
      expect(text, contains(item75.text.trim()));
      for (final p in item75.paragraphs) {
        expect(text, contains(p.trim()));
      }
      for (final fn in item75.footnotes) {
        expect(text, contains(fn.text.trim()));
      }
      expect(text, contains(realRepository.metadata.author));
      expect(text, contains('دار إسلام هاوس'));
      expect(text, contains('https://islamhouse.com/ar/books/2522'));
    });

    for (final size in const [Size(320, 480), Size(480, 320)]) {
      testWidgets('HisnDetailScreen renders without overflow at ${size.width.toInt()}x${size.height.toInt()} textScale 2.0 with full source item 75', (tester) async {
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final clipboardLog = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
          clipboardLog.add(methodCall);
          return null;
        });

        final item75 = realRepository.getById(75)!;

        await tester.pumpWidget(
          buildTestApp(
            mediaQuery: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2.0),
            ),
            child: HisnDetailScreen(item: item75),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Initial load at ${size.width.toInt()}x${size.height.toInt()} textScale 2.0 must not overflow');
        expect(find.byType(HisnDetailScreen), findsOneWidget);
        expect(
          MediaQuery.textScalerOf(tester.element(find.byType(HisnDetailScreen))).scale(10),
          20,
        );

        // Verify copy button in AppBar is hit-testable and copies full text
        final copyBtn = find.byTooltip('نسخ نص الذكر والمراجع');
        expect(copyBtn.hitTestable(), findsOneWidget);
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();

        expect(find.text('تم نسخ نص الذكر والمراجع بنجاح'), findsOneWidget);
        final copyCall = clipboardLog.firstWhere((call) => call.method == 'Clipboard.setData');
        final copiedText = (copyCall.arguments as Map)['text'] as String;
        expect(copiedText, contains(item75.text.trim()));
        for (final fn in item75.footnotes) {
          expect(copiedText, contains(fn.text.trim()));
        }
        expect(copiedText, contains(realRepository.metadata.author));
        expect(copiedText, contains('https://islamhouse.com/ar/books/2522'));

        // Bounded margin drag helper using measured ListView rect (no ensureVisible/no jumpTo)
        final listRect = tester.getRect(find.byType(ListView).first);
        Future<void> scrollUntilVisible(Finder targetFinder, {int maxDrags = 80, double delta = -120.0}) async {
          for (int i = 0; i < maxDrags; i++) {
            if (targetFinder.hitTestable().evaluate().isNotEmpty) return;
            if (targetFinder.evaluate().isNotEmpty) {
              final center = tester.getCenter(targetFinder.first);
              if (center.dy >= listRect.top + 10 && center.dy <= listRect.bottom - 10) return;
            }
            await tester.dragFrom(Offset(listRect.left + 4, listRect.center.dy), Offset(0, delta));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'No RenderFlex overflow during bounded drag towards $targetFinder (step $i)');
          }
          expect(targetFinder.hitTestable(), findsWidgets, reason: 'Target $targetFinder must be hit-testable within bounded margin drags');
        }

        // Scroll to footnotes card and verify all footnotes are visible and non-overflowing
        final fnHeader = find.textContaining('التخريج وهوامش المصدر');
        await scrollUntilVisible(fnHeader);
        expect(fnHeader, findsOneWidget);
        for (final fn in item75.footnotes) {
          final fnFinder = find.textContaining(fn.text.trim());
          await scrollUntilVisible(fnFinder);
          expect(fnFinder, findsWidgets);
        }

        // Scroll to provenance footer card and verify IslamHouse buttons are accessible
        final sourceButton = find.text('صفحة الكتاب في إسلام هاوس');
        await scrollUntilVisible(sourceButton);
        expect(sourceButton, findsOneWidget);
        expect(sourceButton.hitTestable(), findsOneWidget);

        final copyLinkButton = find.text('نسخ الرابط');
        await scrollUntilVisible(copyLinkButton);
        expect(copyLinkButton, findsOneWidget);
        expect(copyLinkButton.hitTestable(), findsOneWidget);
        await tester.tap(copyLinkButton);
        await tester.pumpAndSettle();

        expect(find.text('تم نسخ رابط الكتاب بنجاح'), findsOneWidget);
        final lastCopyCall = clipboardLog.lastWhere((call) => call.method == 'Clipboard.setData');
        expect((lastCopyCall.arguments as Map)['text'], 'https://islamhouse.com/ar/books/2522');
      });
    }
  });

  group('DhikrScreen Sourced Adhkar Integration', () {
    testWidgets('displays morning/evening and post-prayer quick shortcuts and sourced section', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: const DhikrScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Shortcuts at the top
      expect(find.text('أذكار الصباح (٢٢)'), findsOneWidget);
      expect(find.text('أذكار المساء (٢٠)'), findsOneWidget);
      expect(find.text('أذكار بعد الصلاة'), findsOneWidget);

      // Sourced section card
      expect(find.text('أذكار مأثورة موثقة (حصن المسلم)'), findsOneWidget);
      expect(find.text('أذكار الصباح والمساء'), findsOneWidget);
      expect(find.text('فهرس حصن المسلم كاملاً'), findsOneWidget);

      // Personal tasbeeh buttons remain fully present
      expect(find.byTooltip('جلسة جديدة'), findsOneWidget);
      expect(find.byTooltip('تغيير الهدف'), findsOneWidget);
    });

    testWidgets('tapping morning shortcut navigates to DailyHisnChecklistScreen (morning)', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: const DhikrScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the top shortcut for morning
      await tester.tap(find.widgetWithText(OutlinedButton, 'أذكار الصباح (٢٢)'));
      await tester.pumpAndSettle();

      expect(find.byType(DailyHisnChecklistScreen), findsOneWidget);
      expect(find.text('أذكار الصباح (٢٢ ذكراً)'), findsOneWidget);
      expect(find.textContaining('ذكر #75'), findsOneWidget);
    });

    testWidgets('tapping evening shortcut navigates to DailyHisnChecklistScreen (evening)', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: const DhikrScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the top shortcut for evening
      await tester.tap(find.widgetWithText(OutlinedButton, 'أذكار المساء (٢٠)'));
      await tester.pumpAndSettle();

      expect(find.byType(DailyHisnChecklistScreen), findsOneWidget);
      expect(find.text('أذكار المساء (٢٠ ذكراً)'), findsOneWidget);
      expect(find.textContaining('ذكر #75'), findsOneWidget);
    });

    testWidgets('tapping post-prayer shortcut navigates to PostPrayerDailyScreen', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: const DhikrScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the top shortcut for post-prayer
      await tester.tap(find.widgetWithText(OutlinedButton, 'أذكار بعد الصلاة'));
      await tester.pumpAndSettle();

      expect(find.byType(PostPrayerDailyScreen), findsOneWidget);
      expect(find.text('أذكار بعد الصلاة (الباب ٢٥)'), findsOneWidget);
      expect(find.textContaining('دعاء #66'), findsOneWidget);
    });

    testWidgets('tapping Chapter 27 in sourced section navigates to HisnChapterScreen', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: const DhikrScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap chapter 27 link in the sourced section
      await tester.tap(find.text('أذكار الصباح والمساء'));
      await tester.pumpAndSettle();

      expect(find.byType(HisnChapterScreen), findsOneWidget);
      expect(find.text('أَذْكَارُ الصَّـــبَاحِ وَالْمَسَــــاءِ'), findsWidgets);
    });

    testWidgets('cold-start shortcut tap while provider is loading transitions to requested chapter once loaded', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      final completer = Completer<HisnRepository>();

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            hisnRepositoryProvider.overrideWith((ref) => completer.future),
          ],
          child: const DhikrScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap morning/evening chapter link while provider is still loading
      await tester.tap(find.text('أذكار الصباح والمساء'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // DuasScreen is shown with loading indicator
      expect(find.byType(DuasScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('جاري قراءة أذكار حصن المسلم الموثقة...'), findsOneWidget);
      expect(find.byType(HisnChapterScreen), findsNothing);

      // Now complete the loading with the real repository
      completer.complete(realRepository);
      await tester.pumpAndSettle();

      // HisnChapterScreen for Chapter 27 is opened!
      expect(find.byType(HisnChapterScreen), findsOneWidget);
      expect(find.text('أَذْكَارُ الصَّـــبَاحِ وَالْمَسَــــاءِ'), findsWidgets);
    });

    testWidgets('cold-start shortcut tap when error occurs displays retry and navigates on recovery', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      var shouldFail = true;

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            hisnRepositoryProvider.overrideWith((ref) async {
              if (shouldFail) {
                throw Exception('Local asset read failure');
              }
              return realRepository;
            }),
          ],
          child: const DhikrScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap chapter 25 link in the sourced section
      await tester.tap(find.text('الأذكار بعد السلام من الصلاة'));
      await tester.pumpAndSettle();

      // Shows retryable error view
      expect(find.byType(DuasScreen), findsOneWidget);
      expect(find.byType(RetryableErrorView), findsOneWidget);
      expect(find.textContaining('تعذر تحميل أذكار حصن المسلم'), findsOneWidget);
      expect(find.byType(HisnChapterScreen), findsNothing);

      // Fix failure and tap retry
      shouldFail = false;
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();

      // Successfully transitions to Chapter 25
      expect(find.byType(HisnChapterScreen), findsOneWidget);
      expect(find.text('الأَذْكَارُ بَعْــدَ السَّــلاَمِ مِنَ الصَّــلاَةِ'), findsWidgets);
    });
  });

  group('SourcesScreen Hisn al-Muslim Provenance', () {
    testWidgets('displays Hisn al-Muslim verified status and IslamHouse license attribution', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: SourcesScreen(bundle: _TestAssetBundle()),
        ),
      );
      await tester.pump();

      // Verified Content item
      expect(find.textContaining('حصن المسلم من أذكار الكتاب والسنة (٢٦٧ ذكراً ودعاءً)'), findsOneWidget);
      expect(find.text('مدمج ومتحقق من سلامة المصدر'), findsWidgets);

      // Let error card or loaded card settle
      await tester.pumpAndSettle();

      // Even if font loading from Fake bundle errors, Content Status is always visible
      expect(find.textContaining('٢٦٧ ذكراً ودعاءً مأثوراً في ١٣٢ باباً'), findsOneWidget);
    });
  });
}
