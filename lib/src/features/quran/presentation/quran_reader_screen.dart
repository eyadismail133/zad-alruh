import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../progress/data/models/reading_progress.dart';
import '../../progress/presentation/controllers/progress_controller.dart';
import '../data/quran_repository.dart';
import '../data/sources/quran_asset_loader.dart';
import '../domain/models/surah.dart';
import '../domain/models/verse.dart';
import 'controllers/quran_navigation_controller.dart';
import 'utils/quran_ui_utils.dart';
import 'widgets/add_quran_bookmark_dialog.dart';
import 'widgets/page_jump_dialog.dart';

enum ReaderMode { text, mushaf }

/// Offline Holy Quran reader displaying Medina Mushaf pages.
///
/// Restores last read page, autosaves navigation without inferring exact stop verses,
/// provides an honest Mushaf image absence state, and renders verified Tanzil verses
/// with the Amiri Quran font in accessible text mode.
class QuranReaderScreen extends ConsumerStatefulWidget {
  final int? initialPage;
  final VoidCallback? onBack;

  const QuranReaderScreen({super.key, this.initialPage, this.onBack});

  @override
  ConsumerState<QuranReaderScreen> createState() => _QuranReaderScreenState();
}

class _QuranReaderScreenState extends ConsumerState<QuranReaderScreen> {
  int? _currentPage;
  ReaderMode _readerMode = ReaderMode.text;
  PageController? _pageController;

  int get _activePage => _currentPage ?? widget.initialPage ?? 1;

  @override
  void initState() {
    super.initState();
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
                      Container(
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
                        child: Text(
                          'رواية حفص عن عاصم',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.forestPrimary,
                          ),
                        ),
                      ),
                      // Mode Selector (Mushaf Image vs Accessible Text)
                      SegmentedButton<ReaderMode>(
                        segments: const [
                          ButtonSegment<ReaderMode>(
                            value: ReaderMode.text,
                            label: Text(
                              'نص القرآن',
                              style: TextStyle(fontSize: 11),
                            ),
                            icon: Icon(Icons.format_size, size: 14),
                          ),
                          ButtonSegment<ReaderMode>(
                            value: ReaderMode.mushaf,
                            label: Text(
                              'المصحف',
                              style: TextStyle(fontSize: 11),
                            ),
                            icon: Icon(Icons.auto_stories, size: 14),
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
                        return _buildHonestMushafAbsenceState(
                          context,
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

  /// Builds the honest absence state for image Mushaf pages.
  Widget _buildHonestMushafAbsenceState(
    BuildContext context,
    int pageNumber,
    bool isDark,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const SizedBox(height: 20),
          EmptyStateView(
            icon: Icons.menu_book,
            statusTag: 'صفحات المصحف المصورة قيد التدقيق',
            title:
                'المصحف المصور (صفحة ${QuranUiUtils.toArabicDigits(pageNumber)})',
            message:
                'التزاماً بنزاهة وموثوقية المحتوى الديني، صفحات المصحف المصورة (٦٠٤ صفحات من مصحف المدينة المنورة) قيد المراجعة وتدقيق التراخيص المعتمدة ولم تُدرج بعد.\n\nيمكنك الانتقال فوراً إلى وضع النص القرآني الموثق لقراءة وتصفح آيات هذه الصفحة بنص التنزيل العثماني الكامل.',
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark
                  ? AppColors.darkGoldAccent
                  : AppColors.goldAccent,
              foregroundColor: AppColors.textDark,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.format_size, size: 18),
            label: const Text(
              'الانتقال إلى وضع النص القرآني الموثق',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            onPressed: () {
              setState(() {
                _readerMode = ReaderMode.text;
              });
            },
          ),
        ],
      ),
    );
  }

  /// Builds the accessible, verified Tanzil Uthmani text page with Amiri Quran typography.
  Widget _buildAccessibleTextPage(
    BuildContext context,
    QuranRepository repo,
    int pageNumber,
    ReadingProgress? readingProgress,
    bool isDark,
  ) {
    final verses = repo.getVersesForPage(pageNumber);
    if (verses.isEmpty) {
      return const Center(child: Text('لا توجد آيات لهذه الصفحة.'));
    }

    // Determine current Surahs present on this page
    final surahNumbers = <int>{};
    for (final v in verses) {
      surahNumbers.add(v.surahNumber);
    }

    final firstVerse = verses.first;
    final primarySurah = repo.getSurah(firstVerse.surahNumber);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Page Meta Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkCardBorder.withAlpha(60)
                  : const Color(0xFFF2ECE0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'سورة ${primarySurah.name}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppColors.darkGoldAccent
                        : AppColors.goldDark,
                  ),
                ),
                Text(
                  'الجزء ${QuranUiUtils.toArabicDigits(firstVerse.juzNumber)} · صفحة ${QuranUiUtils.toArabicDigits(pageNumber)}',
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
          const SizedBox(height: 12),

          // Render verses grouped by Surah
          ...surahNumbers.map((sNumber) {
            final surah = repo.getSurah(sNumber);
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
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.symmetric(
                        horizontal: BorderSide(
                          color: isDark
                              ? AppColors.darkCardBorder
                              : const Color(0xFFD6C8A8),
                          width: 1.5,
                        ),
                      ),
                      color: isDark
                          ? AppColors.darkSurface
                          : const Color(0xFFFDFBF7),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '۞ سُورَةُ ${surah.name} ۞',
                          style: TextStyle(
                            fontFamily: 'Amiri Quran',
                            fontSize: 18,
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
                            fontSize: 10,
                            color: isDark
                                ? AppColors.darkTextMuted
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Verses List with exact stop marker & tap options
                ...surahVerses.map((verse) {
                  final isStopVerse =
                      readingProgress?.selectedSurah == verse.surahNumber &&
                      readingProgress?.selectedVerse == verse.verseNumber;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isStopVerse
                          ? (isDark
                                ? Colors.amber.shade900.withAlpha(40)
                                : const Color(0xFFFFF7E3))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isStopVerse
                          ? Border.all(
                              color: isDark
                                  ? AppColors.darkGoldAccent
                                  : AppColors.goldAccent,
                            )
                          : null,
                    ),
                    child: InkWell(
                      onTap: () => _showVerseOptions(verse, surah),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4.0,
                          horizontal: 2.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isStopVerse) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.darkGoldAccent
                                        : AppColors.goldDark,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'موضع التوقف الحالي 🔖',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            Semantics(
                              label:
                                  'الآية ${verse.verseNumber} من سورة ${surah.name}',
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: verse.text,
                                      style: TextStyle(
                                        fontFamily: 'Amiri Quran',
                                        fontSize: 21,
                                        height: 2.2,
                                        color: isDark
                                            ? AppColors.darkTextPrimary
                                            : const Color(0xFF1B2921),
                                      ),
                                    ),
                                    TextSpan(
                                      text:
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
                                  ],
                                ),
                                textAlign: TextAlign.justify,
                                textDirection: TextDirection.rtl,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            );
          }),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
