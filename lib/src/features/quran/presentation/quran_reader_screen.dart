import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../progress/data/models/reading_progress.dart';
import '../../progress/presentation/controllers/progress_controller.dart';
import '../data/quran_repository.dart';
import '../data/sources/kfqc_mushaf_catalog.dart';
import '../data/sources/quran_asset_loader.dart';
import '../domain/models/surah.dart';
import '../domain/models/verse.dart';
import 'controllers/quran_navigation_controller.dart';
import 'utils/quran_ui_utils.dart';
import 'widgets/add_quran_bookmark_dialog.dart';
import 'widgets/page_jump_dialog.dart';

enum ReaderMode { mushaf, text }

/// Offline Holy Quran reader displaying Medina Mushaf pages.
///
/// Restores last read page, autosaves navigation without inferring exact stop verses,
/// renders high-fidelity KFQC Medina Mushaf page sheets (Hafs 1441 AH), and provides
/// verified Tanzil verses with the Amiri Quran font in accessible text mode.
class QuranReaderScreen extends ConsumerStatefulWidget {
  final int? initialPage;
  final VoidCallback? onBack;
  final ReaderMode? initialMode;

  const QuranReaderScreen({
    super.key,
    this.initialPage,
    this.onBack,
    this.initialMode,
  });

  @override
  ConsumerState<QuranReaderScreen> createState() => _QuranReaderScreenState();
}

class _QuranReaderScreenState extends ConsumerState<QuranReaderScreen> {
  int? _currentPage;
  late ReaderMode _readerMode;
  PageController? _pageController;

  int get _activePage => _currentPage ?? widget.initialPage ?? 1;

  @override
  void initState() {
    super.initState();
    _readerMode = widget.initialMode ?? ReaderMode.mushaf;
    if (widget.initialPage != null) {
      final initial = widget.initialPage!.clamp(1, 604);
      _currentPage = initial;
      _pageController = PageController(initialPage: initial - 1);
      final controller = ref.read(readingProgressControllerProvider.notifier);
      unawaited(controller.savePageNavigation(initial).catchError((_) {}));
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      ref.read(quranNavigationProvider.notifier).closeReader();
    }
  }

  Future<void> _changePage(int page, {bool animate = false}) async {
    final targetPage = page.clamp(1, 604);
    if (targetPage == _currentPage && animate == false) return;

    setState(() {
      _currentPage = targetPage;
    });

    if (animate && _pageController != null && _pageController!.hasClients) {
      _pageController!.jumpToPage(targetPage - 1);
    }

    ref.read(quranNavigationProvider.notifier).setPage(targetPage);

    // Capture controller and enqueue autosave
    final controller = ref.read(readingProgressControllerProvider.notifier);
    try {
      await controller.savePageNavigation(targetPage);
    } catch (_) {
      // Controller captures error state; error SnackBar handled by ref.listen
    }
  }

  Future<void> _setExactStopVerse(Verse verse) async {
    final controller = ref.read(readingProgressControllerProvider.notifier);
    final reading = ref.read(readingProgressControllerProvider).valueOrNull;
    final isAlreadySelected =
        reading?.selectedSurah == verse.surahNumber &&
        reading?.selectedVerse == verse.verseNumber;

    final targetPage = _activePage;
    final targetSurah = verse.surahNumber;
    final targetVerse = verse.verseNumber;

    if (isAlreadySelected) {
      try {
        await controller.clearStopVerse(targetPage);
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إلغاء تحديد موضع التوقف عند الآية.'),
            ),
          );
        }
      } catch (_) {
        // Handled by controller error state & listener
      }
    } else {
      try {
        await controller.saveExactStopVerse(
          page: targetPage,
          surah: targetSurah,
          verse: targetVerse,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم تحديد موضع التوقف عند الآية ${QuranUiUtils.toArabicDigits(targetVerse)} بنجاح.',
              ),
            ),
          );
        }
      } catch (_) {
        // Handled by controller error state & listener
      }
    }
  }

  void _showVerseOptions(Verse verse, Surah surah) {
    final reading = ref.read(readingProgressControllerProvider).valueOrNull;
    final isCurrentStop =
        reading?.selectedSurah == verse.surahNumber &&
        reading?.selectedVerse == verse.verseNumber;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'سورة ${surah.name} · الآية ${QuranUiUtils.toArabicDigits(verse.verseNumber)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkGoldAccent
                              : AppColors.forestPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurface
                          : AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkCardBorder
                            : AppColors.cardBorder,
                      ),
                    ),
                    child: Text(
                      verse.text,
                      style: const TextStyle(
                        fontFamily: 'Amiri Quran',
                        fontSize: 18,
                        height: 2.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: Icon(
                      isCurrentStop
                          ? Icons.bookmark_remove
                          : Icons.bookmark_added,
                      color: AppColors.goldAccent,
                    ),
                    title: Text(
                      isCurrentStop
                          ? 'إلغاء تحديد موضع التوقف عند هذه الآية'
                          : 'تحديد كموضع توقف عند هذه الآية',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      isCurrentStop
                          ? 'الآية محددة حالياً كموضع توقفك'
                          : 'يحفظ الآية ${QuranUiUtils.toArabicDigits(verse.verseNumber)} كموضع استئناف دقيق',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(_setExactStopVerse(verse));
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.bookmark_add_outlined,
                      color: AppColors.forestPrimary,
                    ),
                    title: const Text(
                      'إضافة علامة مرجعية مخصصة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: const Text(
                      'حفظ علامة باسم مخصص للإشارة لهذه الآية',
                      style: TextStyle(fontSize: 11),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final quranRepo = ref
                          .read(quranRepositoryProvider)
                          .valueOrNull;
                      if (quranRepo != null) {
                        final verses = quranRepo.getVersesForPage(_activePage);
                        await AddQuranBookmarkDialog.show(
                          context,
                          currentPage: _activePage,
                          versesOnPage: verses,
                          initialVerse: verse,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPageJumpDialog() async {
    final selected = await PageJumpDialog.show(
      context,
      initialPage: _activePage,
    );
    if (selected != null && selected != _activePage) {
      await _changePage(selected, animate: true);
    }
  }

  Future<void> _openAddBookmarkDialog(List<Verse> verses) async {
    await AddQuranBookmarkDialog.show(
      context,
      currentPage: _activePage,
      versesOnPage: verses,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(readingProgressControllerProvider, (prev, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: const Text('تعذر حفظ موضع القراءة الحالي.'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () {
                unawaited(
                  ref
                      .read(readingProgressControllerProvider.notifier)
                      .retrySave()
                      .catchError((_) {}),
                );
              },
            ),
          ),
        );
      }
    });

    final quranAsync = ref.watch(quranRepositoryProvider);
    final readingAsync = ref.watch(readingProgressControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_currentPage == null) {
      return readingAsync.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (err, stack) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'العودة إلى الفهرس',
              onPressed: _handleBack,
            ),
            title: const Text('مصحف المدينة المنورة'),
          ),
          body: Center(
            child: RetryableErrorView(
              message: 'تعذر استعادة موضع القراءة السابق.',
              onRetry: () =>
                  ref.read(readingProgressControllerProvider.notifier).retry(),
            ),
          ),
        ),
        data: (reading) {
          final page = reading.lastPage.clamp(1, 604);
          _currentPage = page;
          _pageController = PageController(initialPage: page - 1);
          return _buildReaderScaffold(
            context,
            quranAsync,
            readingAsync,
            isDark,
          );
        },
      );
    }

    return _buildReaderScaffold(context, quranAsync, readingAsync, isDark);
  }

  Widget _buildReaderScaffold(
    BuildContext context,
    AsyncValue<QuranRepository> quranAsync,
    AsyncValue<ReadingProgress> readingAsync,
    bool isDark,
  ) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'العودة إلى الفهرس',
          onPressed: _handleBack,
        ),
        title: const Text('مصحف المدينة المنورة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.pin_outlined),
            tooltip: 'الانتقال إلى صفحة',
            onPressed: _openPageJumpDialog,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'إضافة علامة مرجعية',
            onPressed: () async {
              final verses =
                  quranAsync.valueOrNull?.getVersesForPage(_activePage) ?? [];
              await _openAddBookmarkDialog(verses);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: quranAsync.when(
          data: (quranRepo) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Slim Controls & Mode Toggle Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface
                        : AppColors.cardSurface,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark
                            ? AppColors.darkCardBorder
                            : AppColors.cardBorder,
                      ),
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      // Narration & Mushaf Identity Badge
                      InkWell(
                        onTap: () => _showMushafAttributionDialog(context),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.teal.shade900.withAlpha(50)
                                : AppColors.forestSoftTint,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'مصحف المدينة (حفص)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.forestPrimary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.info_outline,
                                size: 12,
                                color: isDark
                                    ? AppColors.darkTextMuted
                                    : AppColors.forestPrimary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Mode Selector (Mushaf Image vs Accessible Text)
                      SegmentedButton<ReaderMode>(
                        segments: const [
                          ButtonSegment<ReaderMode>(
                            value: ReaderMode.mushaf,
                            label: Text(
                              'المصحف',
                              style: TextStyle(fontSize: 11),
                            ),
                            icon: Icon(Icons.auto_stories, size: 14),
                          ),
                          ButtonSegment<ReaderMode>(
                            value: ReaderMode.text,
                            label: Text(
                              'نص القرآن',
                              style: TextStyle(fontSize: 11),
                            ),
                            icon: Icon(Icons.format_size, size: 14),
                          ),
                        ],
                        selected: {_readerMode},
                        onSelectionChanged: (Set<ReaderMode> selected) {
                          setState(() {
                            _readerMode = selected.first;
                          });
                        },
                      ),
                    ],
                  ),
                ),

                // Quran Page Reader Content
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: 604,
                    reverse:
                        false, // RTL Directionality automatically handles right-to-left
                    onPageChanged: (index) {
                      _changePage(index + 1);
                    },
                    itemBuilder: (context, index) {
                      final pageNumber = index + 1;
                      if (_readerMode == ReaderMode.mushaf) {
                        return _buildMushafImagePage(
                          context,
                          quranRepo,
                          pageNumber,
                          isDark,
                        );
                      }
                      return _buildAccessibleTextPage(
                        context,
                        quranRepo,
                        pageNumber,
                        readingAsync.valueOrNull,
                        isDark,
                      );
                    },
                  ),
                ),

                // Bottom Page Navigation Controls
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface
                        : AppColors.cardSurface,
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? AppColors.darkCardBorder
                            : AppColors.cardBorder,
                      ),
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Next Button (Semantically advances to page + 1)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? AppColors.darkForestPrimary
                              : AppColors.forestPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.arrow_back_ios, size: 14),
                        label: const Text(
                          'التالي',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _activePage < 604
                            ? () => _changePage(_activePage + 1, animate: true)
                            : null,
                      ),

                      // Page Indicator (Clickable to jump)
                      InkWell(
                        onTap: _openPageJumpDialog,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            'صفحة ${QuranUiUtils.toArabicDigits(_activePage)} / ٦٠٤',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkGoldAccent
                                  : AppColors.goldDark,
                            ),
                          ),
                        ),
                      ),

                      // Previous Button (Semantically goes to page - 1)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.arrow_forward_ios, size: 14),
                        label: const Text(
                          'السابق',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: _activePage > 1
                            ? () => _changePage(_activePage - 1, animate: true)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: RetryableErrorView(
                message: 'تعذر تحميل بيانات المصحف الشريف.',
                onRetry: () => ref.refresh(quranRepositoryProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMushafAttributionDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_stories, color: AppColors.forestPrimary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'مصحف المدينة النبوية',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الرواية: حفص عن عاصم الكوفي\n\n'
                'المصدر الأصلي: مجمع الملك فهد لطباعة المصحف الشريف بالمدينة المنورة (طبعة ١٤٤١هـ).\n\n'
                'الترخيص والاستخدام: أتاح المجمع النسخ الرقمية للاستخدام العام في التطبيقات والبرامج والمواقع (الدليل الفني لمجمع الملك فهد، صفحة ٥١، قسم "مصحف المدينة النبوية لأعمال الطباعة").\n\n'
                'التحويل الرقمي: مستودع quran-ws/quran-svg مفتوح المصدر (CC BY 4.0).\n\n'
                'النص القرآني: نص التنزيل العثماني المحقق (مشروع Tanzil.net).',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkCardBorder
                        : AppColors.cardBorder,
                  ),
                ),
                child: Text(
                  'ملاحظة التدقيق: أُجري الفحص البصري التقني للعينات المحورية المعتمدة، ولا ندّعي موافقة رسمية من الناشر للتحويل الرقمي؛ والمراجعة الشرعية البشرية المستقلة قيد المتابعة.',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.5,
                    color: isDark
                        ? AppColors.darkGoldAccent
                        : AppColors.forestMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  /// Builds the high-fidelity KFQC Medina Mushaf image page sheet.
  Widget _buildMushafImagePage(
    BuildContext context,
    QuranRepository repo,
    int pageNumber,
    bool isDark,
  ) {
    return _MushafImageSheet(
      key: ValueKey('mushaf_image_sheet_$pageNumber'),
      repo: repo,
      pageNumber: pageNumber,
      isDark: isDark,
    );
  }

  /// Builds the accessible, verified Tanzil Uthmani text page with Amiri Quran typography
  /// rendered as a true flowing rich-text paragraph on a Medina Mushaf sheet.
  Widget _buildAccessibleTextPage(
    BuildContext context,
    QuranRepository repo,
    int pageNumber,
    ReadingProgress? readingProgress,
    bool isDark,
  ) {
    return _FlowingMushafPage(
      key: ValueKey('flowing_mushaf_page_$pageNumber'),
      repo: repo,
      pageNumber: pageNumber,
      readingProgress: readingProgress,
      isDark: isDark,
      onVerseTap: (verse, surah) => _showVerseOptions(verse, surah),
    );
  }
}

/// A stateful Medina Mushaf page sheet that renders all verses assigned to a page
/// as a continuous, flowing rich-text paragraph per Surah, with individually tappable
/// verse spans and properly disposed [TapGestureRecognizer] instances.
class _FlowingMushafPage extends StatefulWidget {
  final QuranRepository repo;
  final int pageNumber;
  final ReadingProgress? readingProgress;
  final bool isDark;
  final void Function(Verse verse, Surah surah) onVerseTap;

  const _FlowingMushafPage({
    super.key,
    required this.repo,
    required this.pageNumber,
    required this.readingProgress,
    required this.isDark,
    required this.onVerseTap,
  });

  @override
  State<_FlowingMushafPage> createState() => _FlowingMushafPageState();
}

class _FlowingMushafPageState extends State<_FlowingMushafPage> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void didUpdateWidget(covariant _FlowingMushafPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageNumber != widget.pageNumber ||
        oldWidget.readingProgress != widget.readingProgress ||
        oldWidget.isDark != widget.isDark) {
      _clearRecognizers();
    }
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  TapGestureRecognizer _obtainRecognizer(Verse verse, Surah surah) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onVerseTap(verse, surah);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    final verses = widget.repo.getVersesForPage(widget.pageNumber);
    if (verses.isEmpty) {
      return const Center(child: Text('لا توجد آيات لهذه الصفحة.'));
    }

    _clearRecognizers();

    // Determine current Surahs present on this page
    final surahNumbers = <int>{};
    for (final v in verses) {
      surahNumbers.add(v.surahNumber);
    }

    final firstVerse = verses.first;
    final primarySurah = widget.repo.getSurah(firstVerse.surahNumber);
    final isDark = widget.isDark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B231F) : const Color(0xFFFAF7EE),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? AppColors.darkCardBorder : const Color(0xFFD6C8A8),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withAlpha(80)
                  : Colors.brown.withAlpha(20),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Page Meta Header (Slim frame at top of Mushaf sheet)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkCardBorder.withAlpha(40)
                    : const Color(0xFFF1E9DA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkCardBorder
                      : const Color(0xFFE2D8C3),
                  width: 0.8,
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 2,
                children: [
                  Text(
                    'سورة ${primarySurah.name}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkGoldAccent
                          : AppColors.goldDark,
                    ),
                  ),
                  Text(
                    'الجزء ${QuranUiUtils.toArabicDigits(firstVerse.juzNumber)} · صفحة ${QuranUiUtils.toArabicDigits(widget.pageNumber)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Render Surahs and their flowing continuous verses
            ...surahNumbers.map((sNumber) {
              final surah = widget.repo.getSurah(sNumber);
              final surahVerses = verses
                  .where((v) => v.surahNumber == sNumber)
                  .toList();
              final isSurahStart = surahVerses.any((v) => v.verseNumber == 1);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Surah Header Banner if Surah starts on this page
                  if (isSurahStart) ...[
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: isDark
                                ? AppColors.darkGoldAccent.withAlpha(120)
                                : const Color(0xFFC7B38A),
                            width: 1.2,
                          ),
                        ),
                        color: isDark
                            ? AppColors.darkSurface.withAlpha(150)
                            : const Color(0xFFF5EEDB),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '۞ سُورَةُ ${surah.name} ۞',
                            style: TextStyle(
                              fontFamily: 'Amiri Quran',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkGoldAccent
                                  : AppColors.forestPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            '${surah.type == "Meccan" ? "مكية" : "مدنية"} · عدد آياتها ${QuranUiUtils.toArabicDigits(surah.versesCount)}',
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark
                                  ? AppColors.darkTextMuted
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // True flowing rich-text paragraph for this Surah
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 4.0,
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: surahVerses.expand<InlineSpan>((verse) {
                          final isStopVerse =
                              widget.readingProgress?.selectedSurah ==
                                  verse.surahNumber &&
                              widget.readingProgress?.selectedVerse ==
                                  verse.verseNumber;
                          final recognizer = _obtainRecognizer(verse, surah);

                          final spans = <InlineSpan>[];

                          // Stop badge indicator widget span
                          if (isStopVerse) {
                            spans.add(
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.darkGoldAccent
                                        : AppColors.goldDark,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text(
                                    'موضع التوقف الحالي 🔖',
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }

                          // Main verse text span with full semantics label (content, number, and chapter)
                          spans.add(
                            TextSpan(
                              text: '${verse.text} ',
                              semanticsLabel:
                                  '${verse.text} (الآية ${verse.verseNumber} من سورة ${surah.name})',
                              recognizer: recognizer,
                              style: TextStyle(
                                fontFamily: 'Amiri Quran',
                                fontSize: 21,
                                height: 1.85,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : const Color(0xFF1B2921),
                                backgroundColor: isStopVerse
                                    ? (isDark
                                        ? Colors.amber.shade900.withAlpha(90)
                                        : const Color(0xFFFFF1C2))
                                    : null,
                              ),
                            ),
                          );

                          // Ayah ending marker: visually rendered and tappable, but excluded
                          // from separate screen-reader semantics so each verse has exactly one focus target
                          spans.add(
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: ExcludeSemantics(
                                child: GestureDetector(
                                  onTap: () => widget.onVerseTap(verse, surah),
                                  behavior: HitTestBehavior.opaque,
                                  child: Text(
                                    ' ۝${QuranUiUtils.toArabicDigits(verse.verseNumber)} ',
                                    style: TextStyle(
                                      fontFamily: 'Amiri Quran',
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? AppColors.darkGoldAccent
                                          : AppColors.forestMedium,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );

                          return spans;
                        }).toList(),
                      ),
                      textAlign: TextAlign.justify,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ],
              );
            }),

            const SizedBox(height: 8),
            // Page Footer
            Center(
              child: Text(
                '— ${QuranUiUtils.toArabicDigits(widget.pageNumber)} —',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a single complete printed sheet of the Medina Mushaf (Hafs 1441 AH).
///
/// Features:
/// - Fits sheet to screen without cropping ([BoxFit.contain]).
/// - Supports pinch-to-zoom ([InteractiveViewer]) with minScale: 1.0, maxScale: 4.0.
/// - Preserves horizontal swipe page turning at default scale (1.0) by disabling panning when unzoomed.
/// - Double-tap toggles between 1.0x and 2.0x zoom.
/// - Reset zoom button appears when zoomed.
/// - Prominent page indicator and surah metadata header.
/// - Accessible image semantics with Arabic label.
/// - Lazy loaded with graceful error retry UI.
/// - Never inverts image colors in dark theme.
class _MushafImageSheet extends StatefulWidget {
  final QuranRepository repo;
  final int pageNumber;
  final bool isDark;

  const _MushafImageSheet({
    super.key,
    required this.repo,
    required this.pageNumber,
    required this.isDark,
  });

  @override
  State<_MushafImageSheet> createState() => _MushafImageSheetState();
}

class _MushafImageSheetState extends State<_MushafImageSheet> {
  final TransformationController _transformationController =
      TransformationController();
  bool _isZoomed = false;
  int _retryKey = 0;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformationChanged);
  }

  void _onTransformationChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      setState(() {
        _isZoomed = zoomed;
      });
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
    if (_isZoomed) {
      setState(() {
        _isZoomed = false;
      });
    }
  }

  void _toggleZoom() {
    if (_isZoomed) {
      _resetZoom();
    } else {
      _transformationController.value = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
      setState(() {
        _isZoomed = true;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _MushafImageSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageNumber != widget.pageNumber) {
      _resetZoom();
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    AssetImage(KfqcMushafCatalog.assetPathForPage(widget.pageNumber)).evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verses = widget.repo.getVersesForPage(widget.pageNumber);
    final surahIds = <int>{};
    for (final v in verses) {
      surahIds.add(v.surahNumber);
    }
    final surahs = surahIds.map((id) => widget.repo.getSurah(id)).toList();
    final surahNames = surahs.map((s) => s.name).join(' · ');
    final primarySurahTitle =
        surahs.length > 1 ? surahNames : (surahs.isNotEmpty ? 'سورة ${surahs.first.name}' : '');
    final juzNumber = verses.isNotEmpty ? verses.first.juzNumber : 1;
    final isDark = widget.isDark;

    final assetPath = KfqcMushafCatalog.assetPathForPage(widget.pageNumber);

    final semanticLabel =
        'صفحة مصورة رقم ${QuranUiUtils.toArabicDigits(widget.pageNumber)} من مصحف المدينة النبوية، $primarySurahTitle، الجزء ${QuranUiUtils.toArabicDigits(juzNumber)}';

    return Container(
      color: isDark ? const Color(0xFF141916) : const Color(0xFFF3EFE6),
      child: Stack(
        children: [
          // Main Interactive Image Viewer
          Center(
            child: GestureDetector(
              onDoubleTap: _toggleZoom,
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 1.0,
                maxScale: 4.0,
                panEnabled: _isZoomed,
                clipBehavior: Clip.none,
                child: Semantics(
                  image: true,
                  label: semanticLabel,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white, // Genuine white sheet paper; no color inversion in dark mode
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withAlpha(120)
                              : Colors.brown.withAlpha(30),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        assetPath,
                        key: ValueKey('${assetPath}_$_retryKey'),
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: isDark
                                ? AppColors.darkSurface
                                : AppColors.cardSurface,
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.broken_image_outlined,
                                    size: 48,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'تعذر تحميل صورة الصفحة ${QuranUiUtils.toArabicDigits(widget.pageNumber)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'يرجى إعادة المحاولة أو الانتقال إلى وضع القراءة النصية.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppColors.darkTextMuted
                                          : AppColors.textMuted,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _retryKey++;
                                      });
                                    },
                                    icon: const Icon(Icons.refresh, size: 16),
                                    label: const Text('إعادة المحاولة'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Prominent Page Header Badge (Surah, Juz, and prominent page number)
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: IgnorePointer(
              ignoring: _isZoomed,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isZoomed ? 0.0 : 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (isDark ? const Color(0xFF1E2822) : Colors.white)
                        .withAlpha(220),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkCardBorder
                          : const Color(0xFFD6C8A8),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(20),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          primarySurahTitle,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.forestPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkForestPrimary
                              : AppColors.forestSoftTint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'صفحة ${QuranUiUtils.toArabicDigits(widget.pageNumber)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : AppColors.forestPrimary,
                          ),
                        ),
                      ),
                      Text(
                        'الجزء ${QuranUiUtils.toArabicDigits(juzNumber)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Floating Reset Zoom Button when zoomed
          if (_isZoomed)
            Positioned(
              bottom: 16,
              left: 16,
              child: FloatingActionButton.small(
                onPressed: _resetZoom,
                tooltip: 'إعادة ضبط الحجم الطبيعي',
                backgroundColor: isDark
                    ? AppColors.darkForestPrimary
                    : AppColors.forestPrimary,
                foregroundColor: Colors.white,
                child: const Icon(Icons.zoom_out_map, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}
