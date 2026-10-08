import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:zad_alruh/src/core/theme/app_theme.dart';
import 'package:zad_alruh/src/core/widgets/empty_state_view.dart';
import 'package:zad_alruh/src/core/widgets/retryable_error_view.dart';
import 'package:zad_alruh/src/features/hadith/data/hadith_repository_impl.dart';
import 'package:zad_alruh/src/features/hadith/domain/repositories/hadith_repository.dart';
import 'package:zad_alruh/src/features/hadith/presentation/controllers/hadith_provider.dart';
import 'package:zad_alruh/src/features/hadith/presentation/hadith_detail_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/hadith_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/sources_screen.dart';

class _TestAssetBundle extends Fake implements AssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async => '';
}

class _FakeUrlLauncher extends UrlLauncherPlatform {
  String? lastLaunchedUrl;
  LaunchOptions? lastOptions;
  bool returnSuccess = false;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    lastLaunchedUrl = url;
    lastOptions = options;
    return returnSuccess;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List realJsonBytes;
  late HadithRepository realRepository;

  setUpAll(() async {
    // Assert font files exist and load Amiri Quran + all 4 weights of IBM Plex Sans Arabic
    final amiriFile = File('assets/fonts/Amiri-Quran-Regular.ttf');
    expect(await amiriFile.exists(), isTrue, reason: 'Amiri Quran font asset must exist');
    final amiriBytes = await amiriFile.readAsBytes();
    final fontLoaderAmiri = FontLoader('Amiri Quran');
    fontLoaderAmiri.addFont(Future.value(ByteData.sublistView(amiriBytes)));
    await fontLoaderAmiri.load();

    final fontLoaderPlex = FontLoader('IBM Plex Sans Arabic');
    for (final fontPath in [
      'assets/fonts/IBM-Plex-Sans-Arabic-Regular.ttf',
      'assets/fonts/IBM-Plex-Sans-Arabic-Medium.ttf',
      'assets/fonts/IBM-Plex-Sans-Arabic-SemiBold.ttf',
      'assets/fonts/IBM-Plex-Sans-Arabic-Bold.ttf',
    ]) {
      final f = File(fontPath);
      expect(await f.exists(), isTrue, reason: '$fontPath font asset must exist');
      final bytes = await f.readAsBytes();
      fontLoaderPlex.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await fontLoaderPlex.load();

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

    final file = File('assets/content/hadith/hadith-enc-sahih.json');
    expect(await file.exists(), isTrue, reason: 'Hadith JSON asset must exist');
    realJsonBytes = await file.readAsBytes();
    realRepository = HadithRepositoryImpl.fromBytes(realJsonBytes);
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
        hadithRepositoryProvider.overrideWith((ref) => realRepository),
        ...overrides,
      ],
      child: content,
    );
  }

  group('Hadith Corpus Integrity & Repository', () {
    test('bundled JSON parses exactly 3,213 authentic records with v1.7.0 metadata', () {
      expect(realRepository.count, 3213);
      expect(realRepository.metadata.version, 'v1.7.0');
      expect(realRepository.metadata.source, 'https://hadeethenc.com/ar');
      expect(realRepository.metadata.checkUrl, 'https://hadeethenc.com/en/check/ar/v1.7.0');
      expect(realRepository.metadata.selectionGrade, 'صحيح');
      expect(realRepository.metadata.totalRecords, 3213);
    });

    test('corresponds to known original workbook first and last rows', () {
      final first = realRepository.allHadiths.first;
      expect(first.id, 1751);
      expect(first.grade, 'صحيح');
      expect(first.takhrij, 'متفق عليه');
      expect(first.link, 'https://hadeethenc.com/ar/browse/hadith/1751');
      expect(first.title, contains('اغسلنها ثلاثا'));

      final last = realRepository.allHadiths.last;
      expect(last.id, 66541);
      expect(last.grade, 'صحيح');
      expect(last.takhrij, contains('رواه أحمد'));
      expect(last.link, 'https://hadeethenc.com/ar/browse/hadith/66541');
      expect(last.title, contains('لا يزال لسانك رطبا من ذكر الله'));
    });

    test('all 3,213 records possess non-empty essential fields and unique IDs', () {
      final seenIds = <int>{};
      for (final item in realRepository.allHadiths) {
        expect(seenIds.add(item.id), isTrue, reason: 'Duplicate ID: ${item.id}');
        expect(item.id, greaterThan(0));
        expect(item.title.trim().isNotEmpty, isTrue);
        expect(item.hadithText.trim().isNotEmpty, isTrue);
        expect(item.grade, 'صحيح');
        expect(item.takhrij.trim().isNotEmpty, isTrue);
        expect(item.link, 'https://hadeethenc.com/ar/browse/hadith/${item.id}');
      }
      expect(seenIds.length, 3213);
    });

    test('offline diacritic-insensitive search works across titles, text, and IDs', () {
      // Search by text with diacritics / without diacritics
      final res1 = realRepository.search('لسانك رطبا');
      expect(res1, isNotEmpty);
      expect(res1.any((h) => h.id == 66541), isTrue);

      // Search by exact ID (Latin and Arabic-Indic)
      final res2 = realRepository.search('1751');
      expect(res2, isNotEmpty);
      expect(res2.first.id, 1751);

      final res2Arabic = realRepository.search('١٧٥١');
      expect(res2Arabic, isNotEmpty);
      expect(res2Arabic.first.id, 1751);

      // Empty query returns all
      expect(realRepository.search('').length, 3213);
      expect(realRepository.search('   ').length, 3213);
    });

    test('repository throws HadithValidationException on altered SHA-256 hash', () {
      final corrupted = Uint8List.fromList(realJsonBytes);
      corrupted[corrupted.length - 1] ^= 0xFF;

      expect(
        () => HadithRepositoryImpl.fromBytes(corrupted),
        throwsA(isA<HadithValidationException>().having(
          (e) => e.message,
          'message',
          contains('SHA-256 mismatch'),
        )),
      );
    });

    test('repository throws HadithValidationException on non-sahih grade', () {
      final decoded = jsonDecode(utf8.decode(realJsonBytes)) as Map<String, dynamic>;
      final items = (decoded['items'] as List).cast<Map<String, dynamic>>();
      items[0]['grade'] = 'ضعيف'; // Tamper grade
      final tamperedBytes = Uint8List.fromList(utf8.encode(jsonEncode(decoded)));

      expect(
        () => HadithRepositoryImpl.fromBytes(tamperedBytes, verifySha: false),
        throwsA(isA<HadithValidationException>().having(
          (e) => e.message,
          'message',
          contains('unverified grade'),
        )),
      );
    });

    test('repository throws HadithValidationException on count mismatch', () {
      final decoded = jsonDecode(utf8.decode(realJsonBytes)) as Map<String, dynamic>;
      final items = (decoded['items'] as List);
      items.removeLast(); // 3212 items instead of 3213
      final tamperedBytes = Uint8List.fromList(utf8.encode(jsonEncode(decoded)));

      expect(
        () => HadithRepositoryImpl.fromBytes(tamperedBytes, verifySha: false),
        throwsA(isA<HadithValidationException>().having(
          (e) => e.message,
          'message',
          contains('Expected 3213 Hadith items, got 3212'),
        )),
      );
    });

    test('repository throws HadithValidationException on empty essential field', () {
      final decoded = jsonDecode(utf8.decode(realJsonBytes)) as Map<String, dynamic>;
      final items = (decoded['items'] as List).cast<Map<String, dynamic>>();
      items[0]['takhrij'] = ''; // Empty takhrij
      final tamperedBytes = Uint8List.fromList(utf8.encode(jsonEncode(decoded)));

      expect(
        () => HadithRepositoryImpl.fromBytes(tamperedBytes, verifySha: false),
        throwsA(isA<HadithValidationException>().having(
          (e) => e.message,
          'message',
          contains('empty takhrij'),
        )),
      );
    });
  });

  group('HadithScreen UI Presentation & Workflows', () {
    testWidgets('renders list with search field, total count header, and lazy items', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: HadithScreen(repository: realRepository),
        ),
      );
      await tester.pumpAndSettle();

      // Title & search field
      expect(find.text('الأحاديث النبوية الشريفة'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Header info & count
      expect(find.text('موسوعة الأحاديث النبوية (HadeethEnc)'), findsOneWidget);
      expect(find.text('3213 حديثاً صحيحاً'), findsOneWidget);

      // First item is visible
      expect(find.text('#1751'), findsOneWidget);
      expect(find.text('صحيح'), findsWidgets);
      expect(find.text('متفق عليه'), findsOneWidget);
    });

    testWidgets('search filters list, displays results count, and clearing restores all', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: HadithScreen(repository: realRepository),
        ),
      );
      await tester.pumpAndSettle();

      // Enter search term
      await tester.enterText(find.byType(TextField), 'لسانك رطبا');
      await tester.pumpAndSettle();

      // Results header updated
      expect(find.text('نتائج البحث'), findsOneWidget);
      expect(find.textContaining('من 3213'), findsOneWidget);
      expect(find.text('#66541'), findsOneWidget);

      // Clear button tapped
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      // Restored to full 3213 count
      expect(find.text('3213 حديثاً صحيحاً'), findsOneWidget);
      expect(find.text('#1751'), findsOneWidget);
    });

    testWidgets('empty search state shows EmptyStateView with guidance', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        buildTestApp(
          child: HadithScreen(repository: realRepository),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'عبارة_غير_موجودة_قطعا_xyz');
      await tester.pumpAndSettle();

      expect(find.byType(EmptyStateView), findsOneWidget);
      expect(find.text('لم يتم العثور على أحاديث تطابق بحثك'), findsOneWidget);
    });

    testWidgets('tapping hadith card navigates to HadithDetailScreen with full text and attribution', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          child: HadithScreen(repository: realRepository),
        ),
      );
      await tester.pumpAndSettle();

      // Tap first hadith
      await tester.tap(find.text('#1751'));
      await tester.pumpAndSettle();

      // Detail screen opened
      expect(find.byType(HadithDetailScreen), findsOneWidget);
      expect(find.text('حديث #1751'), findsOneWidget);
      expect(find.text('نص الحديث النبوي الشريف'), findsOneWidget);
      expect(find.text('التخريج والمصدر'), findsOneWidget);
      expect(find.text('متفق عليه'), findsOneWidget);

      // Attribution & links
      expect(find.text('المصدر والتوثيق'), findsOneWidget);
      expect(find.textContaining('HadeethEnc.com'), findsWidgets);
      expect(find.textContaining('v1.7.0'), findsWidgets);
      expect(find.text('فتح في المتصفح'), findsOneWidget);
      expect(find.text('نسخ الرابط'), findsOneWidget);
      expect(find.textContaining('لا يدّعي التطبيق اعتماداً أو تحقيقاً علمياً مستقلاً'), findsOneWidget);
    });

    testWidgets('SourcesScreen renders Hadith verified status and attribution card', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          child: SourcesScreen(bundle: _TestAssetBundle()),
        ),
      );
      await tester.pumpAndSettle();

      // Hadith verified item in content status card
      expect(find.text('موسوعة الأحاديث النبوية (٣٢١٣ حديثاً صحيحاً)'), findsOneWidget);
      expect(find.text('مدمج ومتحقق من سلامة المصدر'), findsWidgets);

      // HadeethEnc attribution card
      expect(find.text('نسب المصدر ورخصة موسوعة الأحاديث النبوية (HadeethEnc)'), findsOneWidget);
      expect(find.textContaining('HadeethEnc.com'), findsWidgets);
      expect(find.textContaining('v1.7.0'), findsWidgets);
    });

    testWidgets('HadithScreen error state renders helpful Arabic message and retry control without leaking internal exception', (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      var loadAttempts = 0;

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            hadithRepositoryProvider.overrideWith((ref) async {
              loadAttempts++;
              if (loadAttempts == 1) {
                throw Exception('Internal asset missing: assets/content/hadith/tampered.json with hash abc123');
              }
              return realRepository;
            }),
          ],
          child: const HadithScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Error view rendered with safe message
      expect(find.byType(RetryableErrorView), findsOneWidget);
      expect(
        find.text('تعذر تحميل بيانات الأحاديث النبوية المحلية من ملف الحزمة. يُرجى إعادة المحاولة.'),
        findsOneWidget,
      );
      // Ensures no internal exception details leaked to user
      expect(find.textContaining('Internal asset missing'), findsNothing);
      expect(find.textContaining('tampered.json'), findsNothing);
      expect(find.textContaining('abc123'), findsNothing);

      // Tap retry and verify recovery to data view
      final retryBtn = find.text('إعادة المحاولة');
      expect(retryBtn, findsOneWidget);
      await tester.tap(retryBtn);
      await tester.pumpAndSettle();

      expect(loadAttempts, 2);
      expect(find.text('3213 حديثاً صحيحاً'), findsOneWidget);
      expect(find.byType(RetryableErrorView), findsNothing);
    });

    for (final size in const [Size(320, 480), Size(480, 320)]) {
      testWidgets('HadithScreen and HadithDetailScreen render without overflow at ${size.width.toInt()}x${size.height.toInt()} textScale 2.0 with full source hadith 1751', (tester) async {
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

        final fakeLauncher = _FakeUrlLauncher()..returnSuccess = false;
        final originalLauncher = UrlLauncherPlatform.instance;
        UrlLauncherPlatform.instance = fakeLauncher;
        addTearDown(() {
          UrlLauncherPlatform.instance = originalLauncher;
        });

        final clipboardLog = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
          clipboardLog.add(methodCall);
          return null;
        });

        final hadith1751 = realRepository.allHadiths.firstWhere((h) => h.id == 1751);

        // 1. Initial list view with 2.0 text scale
        await tester.pumpWidget(
          buildTestApp(
            mediaQuery: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2.0),
            ),
            child: const HadithScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Initial load at ${size.width.toInt()}x${size.height.toInt()} textScale 2.0 must not overflow');
        expect(find.byType(HadithScreen), findsOneWidget);

        // 2. Search for ١٧٥١ in Arabic-Indic digits
        final searchField = find.byType(TextField);
        expect(searchField, findsOneWidget);
        await tester.enterText(searchField, '١٧٥١');
        await tester.pumpAndSettle();

        expect(find.text('#1751'), findsOneWidget);

        // 3. Hit tap real card to navigate to HadithDetailScreen
        await tester.tap(find.text('#1751'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Navigation to HadithDetailScreen must not overflow');
        expect(find.byType(HadithDetailScreen), findsOneWidget);

        // 4. Assert actual detail MediaQuery textScaler 2.0 context
        expect(
          MediaQuery.textScalerOf(tester.element(find.byType(HadithDetailScreen))).scale(10),
          20,
        );

        // 5. Initial grade / appbar / title checks on materialized top card
        expect(find.text('حديث #1751'), findsOneWidget);
        expect(find.text(hadith1751.grade), findsWidgets);
        expect(find.text(hadith1751.title), findsOneWidget);

        // 6. Test AppBar copy tooltip action 'نسخ رابط الحديث' copies EXACT hadith.link
        final appBarCopyBtn = find.byTooltip('نسخ رابط الحديث');
        expect(appBarCopyBtn.hitTestable(), findsOneWidget);
        await tester.tap(appBarCopyBtn);
        await tester.pumpAndSettle();

        expect(find.text('تم نسخ رابط الحديث بنجاح: ${hadith1751.link}'), findsOneWidget);
        final firstCopyCall = clipboardLog.lastWhere((call) => call.method == 'Clipboard.setData');
        expect((firstCopyCall.arguments as Map)['text'], hadith1751.link);

        // Await snackbar duration so it dismisses and does not overlay bottom controls
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();

        // 7. Bounded measured ListView margin drag helper (no ensureVisible/jumpTo/hardcoded geometry)
        final listRect = tester.getRect(find.byType(ListView).first);
        Future<void> scrollUntilVisible(Finder targetFinder, {int maxDrags = 40, double delta = -120.0}) async {
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

        // 8. Progressively scroll to actual canonical hadith1751.hadithText and assert FULL original text
        final hadithTextFinder = find.text(hadith1751.hadithText);
        await scrollUntilVisible(hadithTextFinder);
        expect(hadithTextFinder.hitTestable(), findsOneWidget);
        expect(find.text(hadith1751.hadithText), findsOneWidget);

        // 9. Scroll to التخريج والمصدر header (hit) and actual hadith1751.takhrij finder/assert
        final takhrijHeader = find.text('التخريج والمصدر');
        await scrollUntilVisible(takhrijHeader);
        expect(takhrijHeader.hitTestable(), findsOneWidget);

        final takhrijTextFinder = find.text(hadith1751.takhrij);
        await scrollUntilVisible(takhrijTextFinder);
        expect(takhrijTextFinder.hitTestable(), findsOneWidget);
        expect(find.text(hadith1751.takhrij), findsOneWidget);

        // 10. Scroll to source header and assert provenance URLs
        final sourceHeader = find.text('المصدر والتوثيق');
        await scrollUntilVisible(sourceHeader);
        expect(sourceHeader.hitTestable(), findsOneWidget);
        expect(find.textContaining('HadeethEnc.com'), findsWidgets);
        expect(find.textContaining(hadith1751.link), findsWidgets);

        // 11. Actually hit 'فتح في المتصفح' with SDK launcher returning false then stable fallback
        final openUrlButton = find.text('فتح في المتصفح');
        await scrollUntilVisible(openUrlButton);
        expect(openUrlButton.hitTestable(), findsOneWidget);
        await tester.tap(openUrlButton);
        await tester.pumpAndSettle();

        expect(fakeLauncher.lastLaunchedUrl, hadith1751.link);
        expect(find.text('تعذر فتح الرابط في المتصفح الخارجي.'), findsOneWidget);

        // 12. Existing SnackBar 'نسخ الرابط' action copies exact URL
        final snackBarCopyAction = find.widgetWithText(SnackBarAction, 'نسخ الرابط');
        expect(snackBarCopyAction, findsOneWidget);
        await tester.tap(snackBarCopyAction);
        await tester.pumpAndSettle();

        expect(find.text('تم نسخ رابط الحديث بنجاح: ${hadith1751.link}'), findsOneWidget);
        final fallbackCopyCall = clipboardLog.lastWhere((call) => call.method == 'Clipboard.setData');
        expect((fallbackCopyCall.arguments as Map)['text'], hadith1751.link);

        // Await snackbar duration so it dismisses and does not overlay the footer button
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();

        // 13. Source card footer button 'نسخ الرابط' copies exact URL
        final footerCopyButton = find.widgetWithText(OutlinedButton, 'نسخ الرابط');
        await scrollUntilVisible(footerCopyButton);
        expect(footerCopyButton.hitTestable(), findsOneWidget);
        await tester.tap(footerCopyButton);
        await tester.pumpAndSettle();

        expect(find.text('تم نسخ رابط الحديث بنجاح: ${hadith1751.link}'), findsOneWidget);
        final footerCopyCall = clipboardLog.lastWhere((call) => call.method == 'Clipboard.setData');
        expect((footerCopyCall.arguments as Map)['text'], hadith1751.link);
      });
    }
  });
}
