import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/widgets/retryable_error_view.dart';
import 'package:zad_alruh/src/features/dhikr/presentation/dhikr_screen.dart';
import 'package:zad_alruh/src/features/hisn/data/hisn_repository_impl.dart';
import 'package:zad_alruh/src/features/hisn/domain/repositories/hisn_repository.dart';
import 'package:zad_alruh/src/features/hisn/presentation/controllers/hisn_provider.dart';
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

  group('DuasScreen Widget Tests', () {
    testWidgets('renders chapters list with 132 chapters by default', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hisnRepositoryProvider.overrideWith((ref) => realRepository),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: DuasScreen(),
          ),
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hisnRepositoryProvider.overrideWith((ref) => realRepository),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: DuasScreen(),
          ),
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hisnRepositoryProvider.overrideWith((ref) => realRepository),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: DuasScreen(),
          ),
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
      expect(find.textContaining('ذكر #74'), findsWidgets);

      // Clear search
      final clearButton = find.byTooltip('مسح البحث');
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      expect(find.text('الأبواب والفصول (132)'), findsOneWidget);
    });

    testWidgets('tapping chapter opens HisnChapterScreen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hisnRepositoryProvider.overrideWith((ref) => realRepository),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: DuasScreen(),
          ),
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hisnRepositoryProvider.overrideWith((ref) => realRepository),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: DuasScreen(),
          ),
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
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
        log.add(methodCall);
        return null;
      });

      final chapter = realRepository.getChapter(1)!;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: Scaffold(
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

      expect(text, contains('د. سعيد بن علي بن وهف القحطاني'));
      expect(text, contains('دار إسلام هاوس'));
      expect(text, contains('https://islamhouse.com/ar/books/2522'));
      expect(text, contains('الْحَمْدُ للَّهِ الَّذِي أَحْيَانَا'));
    });

    testWidgets('HisnDetailScreen copy button copies text with author, source, and IslamHouse URL', (tester) async {
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
        log.add(methodCall);
        return null;
      });

      final item = realRepository.getById(72)!;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: HisnDetailScreen(item: item),
        ),
      );
      await tester.pumpAndSettle();

      final copyBtn = find.byTooltip('نسخ نص الذكر والمراجع');
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(find.text('تم نسخ نص الذكر والمراجع بنجاح'), findsOneWidget);

      final setClipboardCall = log.firstWhere((call) => call.method == 'Clipboard.setData');
      final text = (setClipboardCall.arguments as Map)['text'] as String;

      expect(text, contains('د. سعيد بن علي بن وهف القحطاني'));
      expect(text, contains('دار إسلام هاوس'));
      expect(text, contains('https://islamhouse.com/ar/books/2522'));
      expect(text, contains('عدد التكرار: 10 مرات'));
    });

    testWidgets('HisnDetailScreen renders without overflow at 320px width with 2.0x text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final item = realRepository.getById(72)!; // item 72 has repeatTarget: 10

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2.0),
            ),
            child: HisnDetailScreen(item: item),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HisnDetailScreen), findsOneWidget);
      expect(find.textContaining('التكرار الوارد في النص:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('DhikrScreen Sourced Adhkar Integration', () {
    testWidgets('displays morning/evening and post-prayer quick shortcuts and sourced section', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hisnRepositoryProvider.overrideWith((ref) => realRepository),
            progressRepositoryProvider.overrideWithValue(testProgressRepo),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: DhikrScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Shortcuts at the top
      expect(find.text('أذكار الصباح والمساء'), findsWidgets);
      expect(find.text('أذكار بعد الصلاة'), findsOneWidget);

      // Sourced section card
      expect(find.text('أذكار مأثورة موثقة (حصن المسلم)'), findsOneWidget);
      expect(find.text('فهرس حصن المسلم كاملاً'), findsOneWidget);

      // Personal tasbeeh buttons remain fully present
      expect(find.byTooltip('جلسة جديدة'), findsOneWidget);
      expect(find.byTooltip('تغيير الهدف'), findsOneWidget);
    });

    testWidgets('tapping morning/evening shortcut navigates to Chapter 27 (أذكار الصباح والمساء)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hisnRepositoryProvider.overrideWith((ref) => realRepository),
            progressRepositoryProvider.overrideWithValue(testProgressRepo),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: DhikrScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the top shortcut for morning/evening
      await tester.tap(find.widgetWithText(OutlinedButton, 'أذكار الصباح والمساء'));
      await tester.pumpAndSettle();

      expect(find.byType(HisnChapterScreen), findsOneWidget);
      expect(find.text('أَذْكَارُ الصَّـــبَاحِ وَالْمَسَــــاءِ'), findsWidgets);
      expect(find.textContaining('الباب'), findsWidgets);
      expect(find.textContaining('أذكار'), findsWidgets);
    });

    testWidgets('tapping post-prayer shortcut navigates to Chapter 25 (الأذكار بعد السلام من الصلاة)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hisnRepositoryProvider.overrideWith((ref) => realRepository),
            progressRepositoryProvider.overrideWithValue(testProgressRepo),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: DhikrScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the top shortcut for post-prayer
      await tester.tap(find.widgetWithText(OutlinedButton, 'أذكار بعد الصلاة'));
      await tester.pumpAndSettle();

      expect(find.byType(HisnChapterScreen), findsOneWidget);
      expect(find.text('الأَذْكَارُ بَعْــدَ السَّــلاَمِ مِنَ الصَّــلاَةِ'), findsWidgets);
      expect(find.textContaining('الباب'), findsWidgets);
      expect(find.textContaining('أذكار'), findsWidgets);
    });

    testWidgets('cold-start shortcut tap while provider is loading transitions to requested chapter once loaded', (tester) async {
      final completer = Completer<HisnRepository>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hisnRepositoryProvider.overrideWith((ref) => completer.future),
            progressRepositoryProvider.overrideWithValue(testProgressRepo),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: DhikrScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap morning/evening shortcut while provider is still loading
      await tester.tap(find.widgetWithText(OutlinedButton, 'أذكار الصباح والمساء'));
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
      var shouldFail = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hisnRepositoryProvider.overrideWith((ref) async {
              if (shouldFail) {
                throw Exception('Local asset read failure');
              }
              return realRepository;
            }),
            progressRepositoryProvider.overrideWithValue(testProgressRepo),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: DhikrScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap shortcut
      await tester.tap(find.widgetWithText(OutlinedButton, 'أذكار بعد الصلاة'));
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
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: SourcesScreen(bundle: _TestAssetBundle()),
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
