import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/theme/app_theme.dart';
import 'package:zad_alruh/src/features/prayer/data/sources/city_asset_adapter.dart';
import 'package:zad_alruh/src/features/prayer/domain/repositories/city_repository.dart';
import 'package:zad_alruh/src/features/progress/data/models/reading_progress.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';
import 'package:zad_alruh/src/features/quran/data/quran_repository.dart';
import 'package:zad_alruh/src/features/quran/data/sources/kfqc_mushaf_catalog.dart';
import 'package:zad_alruh/src/features/quran/data/sources/quran_asset_loader.dart';
import 'package:zad_alruh/src/features/quran/presentation/quran_reader_screen.dart';

bool _fontsLoaded = false;
Future<void> _ensureTestFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();

    final naskh = FontLoader('Noto Naskh Arabic')
      ..addFont(rootBundle.load('assets/fonts/NotoNaskhArabic-Variable.ttf'));
    await naskh.load();
    _fontsLoaded = true;
  });
}

class _TestContext {
  final Directory tempDir;
  final AppDatabase db;
  final ProgressRepository repo;
  final ProviderContainer container;
  bool _disposed = false;

  _TestContext(this.tempDir, this.db, this.repo, this.container);

  static Future<_TestContext> create({
    required QuranRepository quranRepo,
    required CityRepository cityRepo,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('q_layout_test_');
    final db = AppDatabase(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: p.join(tempDir.path, 'q_layout.db'),
    );
    final repo = ProgressRepository(
      db,
      versePageValidator: quranRepo.isValidVerseOnPage,
    );
    final container = ProviderContainer(
      overrides: [
        quranRepositoryProvider.overrideWith((ref) => Future.value(quranRepo)),
        progressRepositoryProvider.overrideWithValue(repo),
        cityRepositoryProvider.overrideWith((ref) async => cityRepo),
      ],
    );
    return _TestContext(tempDir, db, repo, container);
  }

  Future<void> prehydrate([int page = 1]) async {
    await repo.saveReadingProgress(ReadingProgress(lastPage: page));
    await container.read(readingProgressControllerProvider.future);
    await container.read(bookmarksControllerProvider.future);
    await container.read(favoritesControllerProvider.future);
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    try {
      final controller =
          container.read(readingProgressControllerProvider.notifier);
      bool drained = false;
      Object? drainError;
      final drainFuture = controller.drainPendingWrites().then<void>(
        (_) {
          drained = true;
        },
        onError: (Object error, StackTrace stack) {
          drainError = error;
        },
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!drained &&
          drainError == null &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(
        drainError,
        isNull,
        reason: 'Pending writes drain encountered an error: $drainError',
      );
      expect(
        drained,
        isTrue,
        reason:
            'Reading progress controller queue must drain before deadline',
      );
      if (drained) {
        await drainFuture;
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      await tester.runAsync(() async {
        await repo.close();
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
    }
  }
}

Future<void> _awaitDecodedPageImage(
  WidgetTester tester, {
  required int pageNumber,
}) async {
  final expectedAsset = KfqcMushafCatalog.assetPathForPage(pageNumber);
  final imageFinder = find.byWidgetPredicate((widget) {
    if (widget is Image && widget.image is AssetImage) {
      final asset = widget.image as AssetImage;
      return asset.assetName == expectedAsset;
    }
    return false;
  });

  if (imageFinder.evaluate().isNotEmpty) {
    await tester.runAsync(() async {
      final element = tester.element(imageFinder.first);
      await precacheImage(
        AssetImage(expectedAsset),
        element,
      );
    });
  }

  final rawImageFinder = find.descendant(
    of: imageFinder,
    matching: find.byType(RawImage),
  );

  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (rawImageFinder.evaluate().isNotEmpty) {
      final render = tester.renderObject<RenderImage>(rawImageFinder.first);
      if (render.image != null) {
        return;
      }
    }
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

Future<Rect> _getPaintedImageDestinationRect(
  WidgetTester tester, {
  required int pageNumber,
}) async {
  await _awaitDecodedPageImage(tester, pageNumber: pageNumber);

  final expectedAsset = KfqcMushafCatalog.assetPathForPage(pageNumber);
  final imageFinder = find.byWidgetPredicate((widget) {
    if (widget is Image && widget.image is AssetImage) {
      final asset = widget.image as AssetImage;
      return asset.assetName == expectedAsset;
    }
    return false;
  });

  expect(
    imageFinder,
    findsOneWidget,
    reason:
        'Must find exactly one decoded rendered Image for page $pageNumber ($expectedAsset)',
  );

  final rawImageFinder = find.descendant(
    of: imageFinder,
    matching: find.byType(RawImage),
  );
  expect(
    rawImageFinder,
    findsOneWidget,
    reason:
        'Must find decoded descendant RawImage for page $pageNumber ($expectedAsset)',
  );

  final renderImage = tester.renderObject<RenderImage>(rawImageFinder);
  final image = renderImage.image;
  expect(
    image,
    isNotNull,
    reason: 'RenderImage for page $pageNumber must have loaded decoded ui.Image',
  );
  if (image == null) {
    fail('RenderImage for page $pageNumber must have loaded decoded ui.Image');
  }

  final imageSize = Size(image.width.toDouble(), image.height.toDouble());
  final fittedSizes = applyBoxFit(BoxFit.contain, imageSize, renderImage.size);
  final destinationRect = Alignment.center.inscribe(
    fittedSizes.destination,
    Offset.zero & renderImage.size,
  );
  final topLeft = renderImage.localToGlobal(destinationRect.topLeft);
  final bottomRight = renderImage.localToGlobal(destinationRect.bottomRight);
  return Rect.fromPoints(topLeft, bottomRight);
}

Rect _getWidgetGlobalRect(WidgetTester tester, Finder finder) {
  expect(
    finder,
    findsOneWidget,
    reason: 'Finder must match exactly one widget',
  );
  final renderBox = tester.renderObject<RenderBox>(finder);
  final topLeft = renderBox.localToGlobal(Offset.zero);
  return topLeft & renderBox.size;
}

Future<void> _scrollRowUntilHitTestable(
  WidgetTester tester, {
  required Finder target,
  required Finder scrollable,
  double step = 80.0,
  int maxDrags = 15,
}) async {
  expect(
    scrollable,
    findsOneWidget,
    reason: 'Keyed control row scrollable must exist',
  );
  expect(
    target,
    findsWidgets,
    reason: 'Target widget must exist in the widget tree',
  );

  int drags = 0;
  while (target.hitTestable().evaluate().isEmpty && drags < maxDrags) {
    drags++;
    final targetBox = tester.renderObject<RenderBox>(target.first);
    final targetCenter = targetBox.localToGlobal(
      targetBox.size.center(Offset.zero),
    );
    final scrollBox = tester.renderObject<RenderBox>(scrollable);
    final scrollBounds =
        scrollBox.localToGlobal(Offset.zero) & scrollBox.size;

    final dragDelta = targetCenter.dx < scrollBounds.left
        ? Offset(step, 0.0)
        : Offset(-step, 0.0);

    await tester.drag(scrollable, dragDelta);
    await tester.pumpAndSettle();
  }

  expect(
    target.hitTestable(),
    findsOneWidget,
    reason:
        'Target widget must be hitTestable via real drag within keyed control row',
  );
}

Future<void> _pumpReaderScreen(
  WidgetTester tester,
  _TestContext ctx, {
  required int initialPage,
  required Size size,
  required EdgeInsets insets,
  double textScale = 1.0,
  Widget Function(Widget child)? hostBuilder,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = FakeViewPadding(
    left: insets.left,
    top: insets.top,
    right: insets.right,
    bottom: insets.bottom,
  );

  final readerWidget = QuranReaderScreen(
    key: ValueKey('quran_reader_screen_$initialPage'),
    initialPage: initialPage,
  );

  final hostedChild =
      hostBuilder != null ? hostBuilder(readerWidget) : readerWidget;

  await tester.runAsync(
    () => tester.pumpWidget(
      UncontrolledProviderScope(
        container: ctx.container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQueryData(
                size: size,
                padding: insets,
                textScaler: TextScaler.linear(textScale),
              ),
              child: hostedChild,
            ),
          ),
        ),
      ),
    ),
  );

  await tester.runAsync(() async {
    final element = tester.element(find.byType(QuranReaderScreen));
    await precacheImage(
      AssetImage(KfqcMushafCatalog.assetPathForPage(initialPage)),
      element,
    );
  });

  await tester.pumpAndSettle();
}

Future<void> _assertImageBoundedWithoutObstruction({
  required WidgetTester tester,
  required int pageNumber,
}) async {
  expect(
    tester.takeException(),
    isNull,
    reason: 'No Flutter exceptions or RenderFlex overflows permitted',
  );

  final imageRect =
      await _getPaintedImageDestinationRect(tester, pageNumber: pageNumber);
  expect(
    imageRect.width,
    greaterThan(0.0),
    reason: 'Painted image width must be positive',
  );
  expect(
    imageRect.height,
    greaterThan(0.0),
    reason: 'Painted image height must be positive',
  );

  final viewportFinder =
      find.byKey(ValueKey('mushaf_image_viewport_$pageNumber'));
  final badgeFinder =
      find.byKey(ValueKey('mushaf_metadata_badge_$pageNumber'));
  final footerFinder =
      find.byKey(const ValueKey('quran_reader_bottom_controls'));
  final topControlsFinder =
      find.byKey(const ValueKey('quran_reader_top_controls'));

  final viewportRect = _getWidgetGlobalRect(tester, viewportFinder);
  final badgeRect = _getWidgetGlobalRect(tester, badgeFinder);
  final footerRect = _getWidgetGlobalRect(tester, footerFinder);
  final topControlsRect = _getWidgetGlobalRect(tester, topControlsFinder);

  // Assert ALL FOUR edges inside actual current page image viewport
  expect(
    imageRect.left,
    greaterThanOrEqualTo(viewportRect.left - 0.05),
    reason:
        'Left edge of image (${imageRect.left}) must be inside viewport left (${viewportRect.left})',
  );
  expect(
    imageRect.right,
    lessThanOrEqualTo(viewportRect.right + 0.05),
    reason:
        'Right edge of image (${imageRect.right}) must be inside viewport right (${viewportRect.right})',
  );
  expect(
    imageRect.top,
    greaterThanOrEqualTo(viewportRect.top - 0.05),
    reason:
        'Top edge of image (${imageRect.top}) must be inside viewport top (${viewportRect.top})',
  );
  expect(
    imageRect.bottom,
    lessThanOrEqualTo(viewportRect.bottom + 0.05),
    reason:
        'Bottom edge of image (${imageRect.bottom}) must be inside viewport bottom (${viewportRect.bottom})',
  );

  // Initial image destination top must be strictly at or below metadata badge bottom
  expect(
    imageRect.top,
    greaterThanOrEqualTo(badgeRect.bottom),
    reason:
        'Page $pageNumber painted top (${imageRect.top}) must be below metadata badge bottom (${badgeRect.bottom})',
  );

  // Initial image destination bottom must be strictly at or above footer top
  expect(
    imageRect.bottom,
    lessThanOrEqualTo(footerRect.top),
    reason:
        'Page $pageNumber painted bottom (${imageRect.bottom}) must be above footer top (${footerRect.top})',
  );

  // Viewport layout itself must lie below metadata badge and above footer
  expect(
    viewportRect.top,
    greaterThanOrEqualTo(badgeRect.bottom),
    reason:
        'Viewport top (${viewportRect.top}) must lie at or below badge bottom (${badgeRect.bottom})',
  );
  expect(
    viewportRect.bottom,
    lessThanOrEqualTo(footerRect.top),
    reason:
        'Viewport bottom (${viewportRect.bottom}) must lie at or above footer top (${footerRect.top})',
  );

  // Regression: Metadata badge and footer have ZERO pixel intersection with the painted image
  expect(
    badgeRect.overlaps(imageRect),
    isFalse,
    reason:
        'Regression against old Stack overlay: Metadata badge must not overlap any painted page pixels on page $pageNumber',
  );
  expect(
    footerRect.overlaps(imageRect),
    isFalse,
    reason:
        'Footer controls must not overlap any painted page pixels on page $pageNumber',
  );
  expect(
    topControlsRect.overlaps(imageRect),
    isFalse,
    reason:
        'Top controls must not overlap any painted page pixels on page $pageNumber',
  );

  // Non-negative clearances
  expect(imageRect.top - badgeRect.bottom, greaterThanOrEqualTo(0.0));
  expect(footerRect.top - imageRect.bottom, greaterThanOrEqualTo(0.0));

  // No floating zoom reset buttons painted over page pixels at default zoom
  expect(
    find.byIcon(Icons.zoom_out_map),
    findsNothing,
    reason:
        'No floating reset zoom button painted over page pixels at default zoom',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  ensureTimeZonesInitialized();

  late QuranRepository quranRepo;
  late CityRepository cityRepo;

  setUpAll(() async {
    final textBytes =
        await File('assets/content/quran/quran-uthmani.txt').readAsBytes();
    final xmlBytes =
        await File('assets/content/quran/quran-data.xml').readAsBytes();
    quranRepo = QuranRepository.fromBytes(
      textBytes: textBytes,
      xmlBytes: xmlBytes,
    );

    final cityBytes =
        await File('assets/content/cities/cities15000.txt').readAsBytes();
    cityRepo = CityAssetAdapter.fromBytes(cityBytes);
  });

  group('Quran Reader Layout - Bounded Obstruction Fix & Acceptance Gates', () {
    // Parametrized viewport test cases across portrait 360x800 and compact landscape 640x360
    final standardViewports = <({
      String name,
      Size size,
      EdgeInsets insets,
      double textScale,
    })>[
      (
        name: 'Portrait 360x800 @ 1.0x',
        size: const Size(360, 800),
        insets: const EdgeInsets.only(top: 24, bottom: 16),
        textScale: 1.0,
      ),
      (
        name: 'Compact Landscape 640x360 @ 1.0x',
        size: const Size(640, 360),
        insets: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
        textScale: 1.0,
      ),
      (
        name: 'Portrait 360x800 @ 1.5x textScale',
        size: const Size(360, 800),
        insets: const EdgeInsets.only(top: 24, bottom: 16),
        textScale: 1.5,
      ),
      (
        name: 'Compact Landscape 640x360 @ 1.5x textScale',
        size: const Size(640, 360),
        insets: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
        textScale: 1.5,
      ),
      (
        name: 'Portrait 360x800 @ 2.0x textScale',
        size: const Size(360, 800),
        insets: const EdgeInsets.only(top: 24, bottom: 16),
        textScale: 2.0,
      ),
      (
        name: 'Compact Landscape 640x360 @ 2.0x textScale',
        size: const Size(640, 360),
        insets: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
        textScale: 2.0,
      ),
    ];

    for (final vp in standardViewports) {
      testWidgets(
        'Page 3 full 15 lines in ${vp.name} renders bounded inside viewport without chrome overlap',
        (tester) async {
          await _ensureTestFonts(tester);
          final ctx = (await tester.runAsync(
            () => _TestContext.create(
              quranRepo: quranRepo,
              cityRepo: cityRepo,
            ),
          ))!;
          addTearDown(() => ctx.dispose(tester));
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPadding);
          try {
            await tester.runAsync(() => ctx.prehydrate(3));

            await _pumpReaderScreen(
              tester,
              ctx,
              initialPage: 3,
              size: vp.size,
              insets: vp.insets,
              textScale: vp.textScale,
            );

            await _assertImageBoundedWithoutObstruction(
              tester: tester,
              pageNumber: 3,
            );
            expect(find.text('صفحة ٣ / ٦٠٤'), findsOneWidget);
          } finally {
            await ctx.dispose(tester);
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            tester.view.resetPadding();
          }
        },
      );
    }

    testWidgets(
      'Actual Page Jump UI workflow navigates from page 1 to 604 with long metadata and bounded asset',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(
            quranRepo: quranRepo,
            cityRepo: cityRepo,
          ),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        try {
          await tester.runAsync(() => ctx.prehydrate(1));

          // Mount reader at Page 1
          await _pumpReaderScreen(
            tester,
            ctx,
            initialPage: 1,
            size: const Size(360, 800),
            insets: const EdgeInsets.only(top: 24, bottom: 16),
            textScale: 1.0,
          );

          await _assertImageBoundedWithoutObstruction(tester: tester, pageNumber: 1);
          expect(find.text('سورة الفاتحة'), findsWidgets);
          expect(find.text('صفحة ١ / ٦٠٤'), findsOneWidget);

          // Precache target page 604 asset before navigation
          await tester.runAsync(() async {
            final element = tester.element(find.byType(QuranReaderScreen));
            await precacheImage(
              AssetImage(KfqcMushafCatalog.assetPathForPage(604)),
              element,
            );
          });

          // Trigger actual Page Jump Dialog via pin action button
          final pinButton = find.byIcon(Icons.pin_outlined);
          expect(pinButton, findsOneWidget);
          await tester.tap(pinButton);
          await tester.pumpAndSettle();

          // Enter 604 and submit jump dialog
          final jumpDialog = find.byType(AlertDialog);
          expect(jumpDialog, findsOneWidget);
          final jumpTextField = find.descendant(
            of: jumpDialog,
            matching: find.byType(TextField),
          );
          expect(jumpTextField, findsOneWidget);
          await tester.enterText(jumpTextField, '604');
          final confirmBtn = find.descendant(
            of: jumpDialog,
            matching: find.text('انتقال'),
          );
          expect(confirmBtn, findsOneWidget);
          await tester.tap(confirmBtn);
          await tester.pumpAndSettle();

          // Verify page indicator and long 3-surah metadata badge
          expect(find.text('صفحة ٦٠٤ / ٦٠٤'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('mushaf_metadata_badge_604')),
            findsOneWidget,
          );
          final surah112 = quranRepo.getSurah(112);
          final surah113 = quranRepo.getSurah(113);
          final surah114 = quranRepo.getSurah(114);
          final fullHeader =
              '${surah112.name} · ${surah113.name} · ${surah114.name}';
          expect(find.text(fullHeader), findsWidgets);
          expect(find.textContaining(surah112.name), findsWidgets);
          expect(find.textContaining(surah113.name), findsWidgets);
          expect(find.textContaining(surah114.name), findsWidgets);

          // Assert newly navigated page 604 is bounded and rendered without overlap
          await _assertImageBoundedWithoutObstruction(tester: tester, pageNumber: 604);

          // Verify reading progress updated in repository
          final progress = await tester.runAsync(
            () => ctx.repo.getReadingProgress(),
          );
          expect(progress?.lastPage, 604);
        } finally {
          await ctx.dispose(tester);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
        }
      },
    );

    testWidgets(
      'Constrained repro 320x480 textScale 2 with insets and AppShell NavigationBar: reachable horizontal controls, no overflow, bounded page 3 and 604',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(
            quranRepo: quranRepo,
            cityRepo: cityRepo,
          ),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        try {
          await tester.runAsync(() => ctx.prehydrate(3));

          // Host QuranReaderScreen inside a parent Scaffold matching AppShell with actual NavigationBar height (80px)
          Widget appShellHarness(Widget child) {
            return Scaffold(
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: child,
                ),
              ),
              bottomNavigationBar: Center(
                heightFactor: 1.0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: NavigationBar(
                    selectedIndex: 1,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        label: 'الرئيسية',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.menu_book),
                        label: 'القرآن',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.access_time_filled_outlined),
                        label: 'الصلاة',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.auto_awesome_outlined),
                        label: 'الأذكار',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.more_horiz_outlined),
                        label: 'المزيد',
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // Test Page 3 under extreme constraints
          await _pumpReaderScreen(
            tester,
            ctx,
            initialPage: 3,
            size: const Size(320, 480),
            insets: const EdgeInsets.only(top: 24, bottom: 16),
            textScale: 2.0,
            hostBuilder: appShellHarness,
          );

          await _assertImageBoundedWithoutObstruction(tester: tester, pageNumber: 3);

          // Find scrollables for top and bottom controls
          final topControls =
              find.byKey(const ValueKey('quran_reader_top_controls'));
          final topScrollable = find.descendant(
            of: topControls,
            matching: find.byType(Scrollable),
          );
          expect(topScrollable, findsOneWidget);

          final bottomControls =
              find.byKey(const ValueKey('quran_reader_bottom_controls'));
          final bottomScrollable = find.descendant(
            of: bottomControls,
            matching: find.byType(Scrollable),
          );
          expect(bottomScrollable, findsOneWidget);

          expect(find.text('نص القرآن'), findsNothing);
          await tester.tap(find.byTooltip('اختيار آية من الصفحة'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('إلغاء'));
          await tester.pumpAndSettle();
          // Actually scroll to and tap Next page button in bottom bar
          final nextBtn =
              find.widgetWithText(ElevatedButton, 'التالي');
          await _scrollRowUntilHitTestable(
            tester,
            target: nextBtn,
            scrollable: bottomScrollable,
          );
          await tester.tap(nextBtn.hitTestable());
          await tester.pumpAndSettle();

          // Incremented to page 4
          expect(find.text('صفحة ٤ / ٦٠٤'), findsOneWidget);

          // Scroll to and tap Previous page button in bottom bar
          final prevBtn =
              find.widgetWithText(OutlinedButton, 'السابق');
          await _scrollRowUntilHitTestable(
            tester,
            target: prevBtn,
            scrollable: bottomScrollable,
          );
          await tester.tap(prevBtn.hitTestable());
          await tester.pumpAndSettle();

          // Returned to page 3
          expect(find.text('صفحة ٣ / ٦٠٤'), findsOneWidget);
          await _assertImageBoundedWithoutObstruction(tester: tester, pageNumber: 3);

          // Test Page 604 with long 3-surah metadata under the same constrained harness
          await _pumpReaderScreen(
            tester,
            ctx,
            initialPage: 604,
            size: const Size(320, 480),
            insets: const EdgeInsets.only(top: 24, bottom: 16),
            textScale: 2.0,
            hostBuilder: appShellHarness,
          );

          expect(find.text('صفحة ٦٠٤ / ٦٠٤'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('mushaf_metadata_badge_604')),
            findsOneWidget,
          );
          await _assertImageBoundedWithoutObstruction(tester: tester, pageNumber: 604);
        } finally {
          await ctx.dispose(tester);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
        }
      },
    );

    testWidgets(
      'Zoom interaction asserts translation matrix changes on drag without page change, reset returns identity and restores initial destination rect',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(
            quranRepo: quranRepo,
            cityRepo: cityRepo,
          ),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        try {
          await tester.runAsync(() => ctx.prehydrate(3));

          await _pumpReaderScreen(
            tester,
            ctx,
            initialPage: 3,
            size: const Size(360, 800),
            insets: const EdgeInsets.only(top: 24, bottom: 16),
            textScale: 1.0,
          );

          final initialRect =
              await _getPaintedImageDestinationRect(tester, pageNumber: 3);
          final center = initialRect.center;

          final viewerFinder =
              find.byKey(const ValueKey('mushaf_interactive_viewer_3'));
          expect(viewerFinder, findsOneWidget);
          final viewerWidget = tester.widget<InteractiveViewer>(viewerFinder);
          final controller = viewerWidget.transformationController!;
          expect(controller.value, Matrix4.identity());

          // Verify ClipRect ancestor exists around viewport to protect chrome
          final clipFinder = find.ancestor(
            of: viewerFinder,
            matching: find.byType(ClipRect),
          );
          expect(
            clipFinder,
            findsWidgets,
            reason: 'ClipRect ancestor must exist to protect chrome from zoomed overflow',
          );

          // Double-tap at center to trigger 2.0x zoom
          await tester.tapAt(center);
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tapAt(center);
          await tester.pumpAndSettle();

          final zoomedMatrix = controller.value.clone();
          expect(
            zoomedMatrix.getMaxScaleOnAxis(),
            greaterThan(1.05),
            reason: 'Double tap must scale transformation matrix above 1.0',
          );

          // Drag to pan from center
          await tester.dragFrom(center, const Offset(-70, -50));
          await tester.pumpAndSettle();

          final pannedMatrix = controller.value;
          final initialTranslation = zoomedMatrix.getTranslation();
          final pannedTranslation = pannedMatrix.getTranslation();

          // Assert actual transform translation changes on drag
          expect(
            pannedTranslation != initialTranslation,
            isTrue,
            reason:
                'Actual transform translation must change on drag (initial: $initialTranslation, panned: $pannedTranslation)',
          );

          // Assert NO page change occurred during zoom drag
          expect(
            find.text('صفحة ٣ / ٦٠٤'),
            findsOneWidget,
            reason: 'Must remain on page 3 without triggering page navigation during pan',
          );

          // Tap floating reset zoom button
          final resetBtnFinder = find.byIcon(Icons.zoom_out_map);
          expect(resetBtnFinder, findsOneWidget);
          await tester.tap(resetBtnFinder);
          await tester.pumpAndSettle();

          // Assert reset returns identity matrix
          expect(
            controller.value,
            Matrix4.identity(),
            reason: 'Reset button must return transformation matrix to identity',
          );
          expect(find.byIcon(Icons.zoom_out_map), findsNothing);

          // Assert restored full bounded painted destination matches initial rect
          final restoredRect =
              await _getPaintedImageDestinationRect(tester, pageNumber: 3);
          expect(
            restoredRect.top,
            closeTo(initialRect.top, 0.05),
            reason: 'Restored top must match initial unzoomed top',
          );
          expect(
            restoredRect.bottom,
            closeTo(initialRect.bottom, 0.05),
            reason: 'Restored bottom must match initial unzoomed bottom',
          );
          expect(
            restoredRect.left,
            closeTo(initialRect.left, 0.05),
            reason: 'Restored left must match initial unzoomed left',
          );
          expect(
            restoredRect.right,
            closeTo(initialRect.right, 0.05),
            reason: 'Restored right must match initial unzoomed right',
          );

          // Precache page 4 before navigation
          await tester.runAsync(() async {
            final element = tester.element(find.byType(QuranReaderScreen));
            await precacheImage(
              AssetImage(KfqcMushafCatalog.assetPathForPage(4)),
              element,
            );
          });

          // Normal swipe next works after reset
          final pageViewFinder = find.byType(PageView);
          expect(pageViewFinder, findsOneWidget);
          final pageViewBox = tester.renderObject<RenderBox>(pageViewFinder);
          final swipeDistance = pageViewBox.size.width * 0.4;
          await tester.flingFrom(center, Offset(swipeDistance, 0.0), 500.0);
          await tester.pumpAndSettle();

          final pageController =
              tester.widget<PageView>(pageViewFinder).controller!;
          final observedPage = pageController.page;
          final observedLabels = find
              .textContaining('صفحة ')
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .toList();
          expect(
            find.text('صفحة ٤ / ٦٠٤'),
            findsOneWidget,
            reason:
                'Single-page image swipe from page 3 must advance to exact page 4 (observed PageController.page: $observedPage, observed labels: $observedLabels)',
          );
        } finally {
          await ctx.dispose(tester);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
        }
      },
    );

    testWidgets(
      'Zoom lifecycle: verse picker preserves zoom, reset restores normal swipe',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(
            quranRepo: quranRepo,
            cityRepo: cityRepo,
          ),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        try {
          await tester.runAsync(() => ctx.prehydrate(3));

          await _pumpReaderScreen(
            tester,
            ctx,
            initialPage: 3,
            size: const Size(360, 800),
            insets: const EdgeInsets.only(top: 24, bottom: 16),
            textScale: 1.0,
          );

          final initialRect =
              await _getPaintedImageDestinationRect(tester, pageNumber: 3);
          final center = initialRect.center;

          // Double-tap to genuinely zoom on page 3
          await tester.tapAt(center);
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tapAt(center);
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);

          final topControls =
              find.byKey(const ValueKey('quran_reader_top_controls'));
          final topScrollable = find.descendant(
            of: topControls,
            matching: find.byType(Scrollable),
          );
          expect(topScrollable, findsOneWidget);

          await tester.tap(find.byTooltip('اختيار آية من الصفحة'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('إلغاء'));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);
          await tester.tap(find.byIcon(Icons.zoom_out_map));
          await tester.pumpAndSettle();
          // Precache page 4 before navigation
          await tester.runAsync(() async {
            final element = tester.element(find.byType(QuranReaderScreen));
            await precacheImage(
              AssetImage(KfqcMushafCatalog.assetPathForPage(4)),
              element,
            );
          });

          // Normal swipe next works after mode switch
          final pageViewFinder = find.byType(PageView);
          expect(pageViewFinder, findsOneWidget);
          final pageViewBox = tester.renderObject<RenderBox>(pageViewFinder);
          final swipeDistance = pageViewBox.size.width * 0.4;
          await tester.flingFrom(center, Offset(swipeDistance, 0.0), 500.0);
          await tester.pumpAndSettle();

          final pageController =
              tester.widget<PageView>(pageViewFinder).controller!;
          final observedPage = pageController.page;
          final observedLabels = find
              .textContaining('صفحة ')
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .toList();
          expect(
            find.text('صفحة ٤ / ٦٠٤'),
            findsOneWidget,
            reason:
                'Single-page image swipe from page 3 must advance to exact page 4 (observed PageController.page: $observedPage, observed labels: $observedLabels)',
          );
        } finally {
          await ctx.dispose(tester);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
        }
      },
    );

    testWidgets(
      'Zoom lifecycle: navigating via Next button and Page Jump while genuinely zoomed resets zoom state and allows normal swipe',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(
            quranRepo: quranRepo,
            cityRepo: cityRepo,
          ),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        try {
          await tester.runAsync(() => ctx.prehydrate(3));

          await _pumpReaderScreen(
            tester,
            ctx,
            initialPage: 3,
            size: const Size(360, 800),
            insets: const EdgeInsets.only(top: 24, bottom: 16),
            textScale: 1.0,
          );

          final initialRect =
              await _getPaintedImageDestinationRect(tester, pageNumber: 3);
          final center = initialRect.center;

          // Double-tap to genuinely zoom on page 3
          await tester.tapAt(center);
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tapAt(center);
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);

          // Precache target page 4 before navigation
          await tester.runAsync(() async {
            final element = tester.element(find.byType(QuranReaderScreen));
            await precacheImage(
              AssetImage(KfqcMushafCatalog.assetPathForPage(4)),
              element,
            );
          });

          // Tap Next button in bottom controls while page 3 is zoomed
          final nextBtn = find.widgetWithText(ElevatedButton, 'التالي');
          expect(nextBtn, findsOneWidget);
          await tester.tap(nextBtn);
          await tester.pumpAndSettle();

          expect(find.text('صفحة ٤ / ٦٠٤'), findsOneWidget);
          // Destination page 4 must be unzoomed
          expect(find.byIcon(Icons.zoom_out_map), findsNothing);

          // Precache target page 5 before swipe
          await tester.runAsync(() async {
            final element = tester.element(find.byType(QuranReaderScreen));
            await precacheImage(
              AssetImage(KfqcMushafCatalog.assetPathForPage(5)),
              element,
            );
          });

          // Normal swipe next works on page 4
          final p4Rect =
              await _getPaintedImageDestinationRect(tester, pageNumber: 4);
          final p4Center = p4Rect.center;
          final pageViewFinder = find.byType(PageView);
          expect(pageViewFinder, findsOneWidget);
          final pageViewBox = tester.renderObject<RenderBox>(pageViewFinder);
          final swipeDistance = pageViewBox.size.width * 0.4;
          await tester.flingFrom(p4Center, Offset(swipeDistance, 0.0), 500.0);
          await tester.pumpAndSettle();

          final pageController =
              tester.widget<PageView>(pageViewFinder).controller!;
          final observedPage = pageController.page;
          final observedLabels = find
              .textContaining('صفحة ')
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .toList();
          expect(
            find.text('صفحة ٥ / ٦٠٤'),
            findsOneWidget,
            reason:
                'Single-page image swipe from page 4 must advance to exact page 5 (observed PageController.page: $observedPage, observed labels: $observedLabels)',
          );

          // Double-tap to zoom on page 5
          final p5Rect =
              await _getPaintedImageDestinationRect(tester, pageNumber: 5);
          await tester.tapAt(p5Rect.center);
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tapAt(p5Rect.center);
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);

          // Precache target page 604 asset before jump
          await tester.runAsync(() async {
            final element = tester.element(find.byType(QuranReaderScreen));
            await precacheImage(
              AssetImage(KfqcMushafCatalog.assetPathForPage(604)),
              element,
            );
          });

          // Trigger Page Jump Dialog while page 5 is zoomed
          final pinButton = find.byIcon(Icons.pin_outlined);
          await tester.tap(pinButton);
          await tester.pumpAndSettle();

          final jumpDialog = find.byType(AlertDialog);
          expect(jumpDialog, findsOneWidget);
          final jumpTextField = find.descendant(
            of: jumpDialog,
            matching: find.byType(TextField),
          );
          await tester.enterText(jumpTextField, '604');
          final confirmBtn = find.descendant(
            of: jumpDialog,
            matching: find.text('انتقال'),
          );
          await tester.tap(confirmBtn);
          await tester.pumpAndSettle();

          expect(find.text('صفحة ٦٠٤ / ٦٠٤'), findsOneWidget);
          expect(find.byIcon(Icons.zoom_out_map), findsNothing);
          await _assertImageBoundedWithoutObstruction(tester: tester, pageNumber: 604);
        } finally {
          await ctx.dispose(tester);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
        }
      },
    );

    testWidgets(
      'Zoom lifecycle: unmounting reader screen while genuinely zoomed disposes cleanly without exception or pending timers',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(
            quranRepo: quranRepo,
            cityRepo: cityRepo,
          ),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        try {
          await tester.runAsync(() => ctx.prehydrate(3));

          await _pumpReaderScreen(
            tester,
            ctx,
            initialPage: 3,
            size: const Size(360, 800),
            insets: const EdgeInsets.only(top: 24, bottom: 16),
            textScale: 1.0,
          );

          final initialRect =
              await _getPaintedImageDestinationRect(tester, pageNumber: 3);
          final center = initialRect.center;

          // Double-tap to genuinely zoom on page 3
          await tester.tapAt(center);
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tapAt(center);
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);

          // Unmount the screen completely WHILE zoomed
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();

          expect(tester.takeException(), isNull);
        } finally {
          await ctx.dispose(tester);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
        }
      },
    );
  });
}
