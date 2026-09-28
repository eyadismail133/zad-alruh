import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List realJsonBytes;
  late HadithRepository realRepository;

  setUpAll(() async {
    final file = File('assets/content/hadith/hadith-enc-sahih.json');
    expect(await file.exists(), isTrue, reason: 'Hadith JSON asset must exist');
    realJsonBytes = await file.readAsBytes();
    realRepository = HadithRepositoryImpl.fromBytes(realJsonBytes);
  });

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

      // Search by exact ID
      final res2 = realRepository.search('1751');
      expect(res2, isNotEmpty);
      expect(res2.first.id, 1751);

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
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: HadithScreen(repository: realRepository),
          ),
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
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: HadithScreen(repository: realRepository),
          ),
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
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: HadithScreen(repository: realRepository),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'عبارة_غير_موجودة_قطعا_xyz');
      await tester.pumpAndSettle();

      expect(find.byType(EmptyStateView), findsOneWidget);
      expect(find.text('لم يتم العثور على أحاديث تطابق بحثك'), findsOneWidget);
    });

    testWidgets('tapping hadith card navigates to HadithDetailScreen with full text and attribution', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: HadithScreen(repository: realRepository),
          ),
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
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SourcesScreen(bundle: _TestAssetBundle()),
        ),
      );
      await tester.pumpAndSettle();

      // Hadith verified item in content status card
      expect(find.text('موسوعة الأحاديث النبوية (٣٢١٣ حديثاً صحيحاً)'), findsOneWidget);
      expect(find.text('مدمج ومتحقق من سلامة المصدر'), findsOneWidget);

      // HadeethEnc attribution card
      expect(find.text('نسب المصدر ورخصة موسوعة الأحاديث النبوية (HadeethEnc)'), findsOneWidget);
      expect(find.textContaining('HadeethEnc.com'), findsWidgets);
      expect(find.textContaining('v1.7.0'), findsWidgets);
    });

    testWidgets('HadithScreen error state renders helpful Arabic message and retry control without leaking internal exception', (tester) async {
      var loadAttempts = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hadithRepositoryProvider.overrideWith((ref) async {
              loadAttempts++;
              if (loadAttempts == 1) {
                throw Exception('Internal asset missing: assets/content/hadith/tampered.json with hash abc123');
              }
              return realRepository;
            }),
          ],
          child: const MaterialApp(
            home: HadithScreen(),
          ),
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
  });
}
