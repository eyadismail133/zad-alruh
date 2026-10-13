import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../prayers/presentation/controllers/adhan_audio_controller.dart';
import '../../progress/data/models/reading_progress.dart';
import '../../progress/data/models/favorite.dart';
import 'widgets/page_verse_selector.dart';
import '../../progress/presentation/controllers/progress_controller.dart';
import '../../progress/presentation/widgets/quran_page_confirmation_control.dart';
import '../data/quran_repository.dart';
import '../data/sources/kfqc_mushaf_catalog.dart';
import '../data/sources/quran_asset_loader.dart';
import '../domain/models/quran_audio_source.dart';
import '../domain/models/verse.dart';
import 'controllers/quran_navigation_controller.dart';
import 'utils/quran_ui_utils.dart';
import 'widgets/add_quran_bookmark_dialog.dart';
import 'widgets/page_jump_dialog.dart';

/// Offline Holy Quran reader displaying Medina Mushaf pages.
///
/// Restores last read page, autosaves navigation without inferring exact stop verses,
/// renders high-fidelity KFQC Medina Mushaf page sheets (Hafs 1441 AH), and provides
/// verse references selected from canonical page metadata.
class QuranReaderScreen extends ConsumerStatefulWidget {
  final int? initialPage;
  final VoidCallback? onBack;

  const QuranReaderScreen({super.key, this.initialPage, this.onBack});

  @override
  ConsumerState<QuranReaderScreen> createState() => _QuranReaderScreenState();
}

class _QuranReaderScreenState extends ConsumerState<QuranReaderScreen> {
  int? _currentPage;
  PageController? _pageController;
  AdhanAudioController? _adhanAudioController;
  bool _isZoomed = false;

  int get _activePage => _currentPage ?? widget.initialPage ?? 1;

  @override
  void initState() {
    super.initState();
    _adhanAudioController = ref.read(adhanAudioControllerProvider.notifier);
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
    _adhanAudioController?.stop().catchError((_) {});
    super.dispose();
  }

  void _handleBack() {
    _adhanAudioController?.stop().catchError((_) {});
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

    if (mounted) {
      setState(() {
        _currentPage = targetPage;
        _isZoomed = false;
      });
    }

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

  Future<void> _choosePageVerse(QuranRepository repository) async {
    final verses = repository.getVersesForPage(_activePage);
    Verse selected = verses.first;
    final verse = await showDialog<Verse>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختيار آية من الصفحة'),
        content: SingleChildScrollView(
          child: PageVerseSelector(
            verses: verses,
            onChanged: (value) => selected = value!,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, selected),
            child: const Text('اختيار'),
          ),
        ],
      ),
    );
    if (verse == null || !mounted) return;
    _showVerseOptions(verse, repository);
  }

  void _showVerseOptions(Verse verse, QuranRepository repository) {
    final reading = ref.read(readingProgressControllerProvider).valueOrNull;
    final isCurrentStop =
        reading?.selectedSurah == verse.surahNumber &&
        reading?.selectedVerse == verse.verseNumber;
    final surah = repository.getSurah(verse.surahNumber);
    final favorites = ref.read(favoritesControllerProvider).valueOrNull ?? [];
    final isFavorite = favorites.any(
      (f) => f.contentKind == 'quran' && f.stableId == verse.id,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'سورة ${surah.name} · الآية ${QuranUiUtils.toArabicDigits(verse.verseNumber)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.bookmark_added),
                  title: Text(
                    isCurrentStop
                        ? 'إلغاء تحديد موضع التوقف عند هذه الآية'
                        : 'تحديد كموضع توقف عند هذه الآية',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_setExactStopVerse(verse));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: const Text('إضافة علامة مرجعية مخصصة'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await AddQuranBookmarkDialog.show(
                      context,
                      currentPage: _activePage,
                      versesOnPage: repository.getVersesForPage(_activePage),
                      initialVerse: verse,
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                  ),
                  title: Text(
                    isFavorite
                        ? 'إزالة الآية من المفضلة'
                        : 'إضافة الآية إلى المفضلة',
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await ref
                          .read(favoritesControllerProvider.notifier)
                          .toggleFavorite(
                            Favorite(
                              contentKind: 'quran',
                              stableId: verse.id,
                              title:
                                  'سورة ${surah.name} · الآية ${QuranUiUtils.toArabicDigits(verse.verseNumber)}',
                              subtitle:
                                  'صفحة ${QuranUiUtils.toArabicDigits(verse.pageNumber)}',
                            ),
                          );
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'تعذر حفظ المفضلة. يرجى المحاولة مجدداً.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
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
            title: const Text('المصحف المصوّر'),
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
          final page = reading.resumePage.clamp(1, 604);
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
    _adhanAudioController = ref.watch(adhanAudioControllerProvider.notifier);
    final audioState = ref.watch(adhanAudioControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'العودة إلى الفهرس',
          onPressed: _handleBack,
        ),
        title: const Text('المصحف المصوّر'),
        actions: [
          IconButton(
            tooltip: 'اختيار آية من الصفحة',
            icon: const Icon(Icons.touch_app_outlined),
            onPressed: quranAsync.valueOrNull == null
                ? null
                : () => _choosePageVerse(quranAsync.requireValue),
          ),
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
                  key: const ValueKey('quran_reader_top_controls'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Narration & Mushaf Identity Badge
                                  InkWell(
                                    onTap: () =>
                                        _showMushafAttributionDialog(context),
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
                                  const SizedBox(width: 8),
                                  // Audio Recitation Selection Button
                                  InkWell(
                                    key: const ValueKey(
                                      'quran_audio_select_button',
                                    ),
                                    onTap: () => _showSurahAudioSelectionDialog(
                                      context,
                                      quranRepo,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: audioState.isSurahActive
                                            ? (isDark
                                                  ? Colors.amber.shade900
                                                        .withAlpha(50)
                                                  : AppColors.goldSoftTint)
                                            : (isDark
                                                  ? Colors.teal.shade900
                                                        .withAlpha(50)
                                                  : AppColors.forestSoftTint),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            key: const ValueKey(
                                              'quran_reader_audio_button',
                                            ),
                                            audioState.isSurahActive
                                                ? Icons.headphones
                                                : Icons.headphones_outlined,
                                            size: 12,
                                            color: audioState.isSurahActive
                                                ? (isDark
                                                      ? AppColors.darkGoldAccent
                                                      : AppColors.goldDark)
                                                : (isDark
                                                      ? AppColors
                                                            .darkTextPrimary
                                                      : AppColors
                                                            .forestPrimary),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            audioState.isSurahActive
                                                ? 'تلاوة سورة ${audioState.activeSurahName ?? ''}'
                                                : 'استماع للسورة',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: audioState.isSurahActive
                                                  ? (isDark
                                                        ? AppColors
                                                              .darkGoldAccent
                                                        : AppColors.goldDark)
                                                  : (isDark
                                                        ? AppColors
                                                              .darkTextPrimary
                                                        : AppColors
                                                              .forestPrimary),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (readingAsync.valueOrNull?.selectedSurah !=
                                      null &&
                                  readingAsync.valueOrNull?.lastPage ==
                                      _activePage)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 8,
                                  ),
                                  child: Text(
                                    'موضع التوقف · الآية ${QuranUiUtils.toArabicDigits(readingAsync.requireValue.selectedVerse!)}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Active Quran Audio Bar (only shown when audio is active)
                if (audioState.sourceType == AudioPlaybackSource.quran &&
                    (audioState.isPlaying ||
                        audioState.isLoading ||
                        audioState.isBuffering ||
                        audioState.isPaused ||
                        audioState.hasError))
                  _buildActiveAudioBar(context, quranRepo, audioState, isDark),

                // Quran Page Reader Content
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    physics: _isZoomed
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    itemCount: 604,
                    reverse:
                        false, // RTL Directionality automatically handles right-to-left
                    onPageChanged: (index) {
                      _changePage(index + 1);
                    },
                    itemBuilder: (context, index) {
                      final pageNumber = index + 1;
                      return _buildMushafImagePage(
                        context,
                        quranRepo,
                        pageNumber,
                        isDark,
                      );
                    },
                  ),
                ),

                // Bottom Page Navigation Controls
                Container(
                  key: const ValueKey('quran_reader_bottom_controls'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                    vertical: 6,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.arrow_back_ios,
                                  size: 14,
                                ),
                                label: const Text(
                                  'التالي',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: _activePage < 604
                                    ? () => _changePage(
                                        _activePage + 1,
                                        animate: true,
                                      )
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
                              const SizedBox(width: 8),

                              // Page Confirmation Control in normal-flow footer
                              QuranPageConfirmationControl(
                                pageNumber: _activePage,
                              ),
                              const SizedBox(width: 8),

                              // Previous Button (Semantically goes to page - 1)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                ),
                                label: const Text(
                                  'السابق',
                                  style: TextStyle(fontSize: 12),
                                ),
                                onPressed: _activePage > 1
                                    ? () => _changePage(
                                        _activePage - 1,
                                        animate: true,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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

  Widget _buildActiveAudioBar(
    BuildContext context,
    QuranRepository quranRepo,
    AdhanAudioState audioState,
    bool isDark,
  ) {
    final controller = ref.read(adhanAudioControllerProvider.notifier);

    return Container(
      key: const ValueKey('quran_active_audio_bar'),
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : const Color(0xFFF0F5F1),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Stop button
                      IconButton(
                        key: const ValueKey('quran_audio_stop_button'),
                        icon: const Icon(Icons.stop, size: 18),
                        tooltip: 'إيقاف التلاوة',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        color: isDark
                            ? Colors.red.shade300
                            : Colors.red.shade700,
                        onPressed: () => controller.stop(),
                      ),
                      const SizedBox(width: 4),
                      // State indicator / control
                      if (audioState.isLoading || audioState.isBuffering) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                      ] else if (audioState.hasError) ...[
                        IconButton(
                          key: const ValueKey('quran_audio_retry_button'),
                          icon: const Icon(Icons.refresh, size: 18),
                          tooltip: 'إعادة المحاولة',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: () {
                            if (audioState.activeSurahNumber != null) {
                              controller.playSurah(
                                surahNumber: audioState.activeSurahNumber!,
                                surahName: audioState.activeSurahName ?? '',
                              );
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                      ] else if (audioState.isPlaying) ...[
                        IconButton(
                          key: const ValueKey('quran_audio_pause_button'),
                          icon: const Icon(Icons.pause, size: 18),
                          tooltip: 'إيقاف مؤقت',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: () => controller.pause(),
                        ),
                        const SizedBox(width: 4),
                      ] else if (audioState.isPaused) ...[
                        IconButton(
                          key: const ValueKey('quran_audio_resume_button'),
                          icon: const Icon(Icons.play_arrow, size: 18),
                          tooltip: 'استئناف',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: () => controller.resume(),
                        ),
                        const SizedBox(width: 4),
                      ],
                      // Surah name
                      Text(
                        'سورة ${audioState.activeSurahName ?? ''}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkGoldAccent
                              : AppColors.goldDark,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Subtitle / Status
                      Text(
                        audioState.isLoading
                            ? 'جاري التحميل...'
                            : audioState.isBuffering
                            ? 'تخزين مؤقت...'
                            : audioState.isPaused
                            ? 'متوقف مؤقتاً'
                            : audioState.hasError
                            ? 'تعذر التحميل'
                            : 'مشاري العفاسي (حفص)',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  // Duration progress display
                  if (audioState.totalDuration > Duration.zero)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: Text(
                        '${_formatDuration(audioState.position)} / ${_formatDuration(audioState.totalDuration)}',
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _showSurahAudioSelectionDialog(
    BuildContext context,
    QuranRepository repo,
  ) {
    final pageVerses = repo.getVersesForPage(_activePage);
    final surahNumbers = pageVerses.map((v) => v.surahNumber).toSet().toList()
      ..sort();
    final pageSurahs = surahNumbers.map((n) => repo.getSurah(n)).toList();
    final allSurahs = repo.getSurahs();
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
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.headphones,
                              color: isDark
                                  ? AppColors.darkGoldAccent
                                  : AppColors.forestPrimary,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            const Flexible(
                              child: Text(
                                'استماع للسورة كاملة',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(),
                  // Source & Provider Info Card
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'القارئ: الشيخ ${QuranAudioSource.reciterName}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'الرواية: ${QuranAudioSource.riwayahName}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppColors.darkTextMuted
                                : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'المصدر: موقع MP3Quran (MP3Quran.net)',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppColors.darkTextMuted
                                : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'تنبيه: يتطلب الاستماع اتصالاً نشطاً بالإنترنت للبث المباشر. تلاوة السورة كاملة ولا تتزامن مع الآيات الفردية أو تقليب الصفحات.',
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.4,
                            color: isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.forestMedium,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            launchUrl(
                              Uri.parse(QuranAudioSource.privacyPolicyUrl),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          child: Text(
                            'سياسة الخصوصية وترخيص المصدر (MP3Quran) ↗',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                              color: isDark
                                  ? AppColors.darkGoldAccent
                                  : AppColors.forestPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Available Surahs on Current Page
                  Text(
                    'السور في الصفحة الحالية (${QuranUiUtils.toArabicDigits(_activePage)}):',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...pageSurahs.map((surah) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? AppColors.darkForestPrimary.withAlpha(50)
                                : AppColors.forestSoftTint,
                          ),
                          child: Center(
                            child: Text(
                              QuranUiUtils.toArabicDigits(surah.number),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.forestPrimary,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          'سورة ${surah.name}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '${surah.type == "Meccan" ? "مكية" : "مدنية"} · ${QuranUiUtils.toArabicDigits(surah.versesCount)} آية',
                          style: const TextStyle(fontSize: 10),
                        ),
                        trailing: ElevatedButton.icon(
                          key: ValueKey('play_page_surah_${surah.number}'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark
                                ? AppColors.darkForestPrimary
                                : AppColors.forestPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text(
                            'استماع',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            ref
                                .read(adhanAudioControllerProvider.notifier)
                                .playSurah(
                                  surahNumber: surah.number,
                                  surahName: surah.name,
                                );
                          },
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  // Dropdown / Selection for All 114 Surahs
                  Theme(
                    data: Theme.of(
                      ctx,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: const Text(
                        'اختيار سورة أخرى من الـ ١١٤ سورة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      children: [
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            itemCount: allSurahs.length,
                            itemBuilder: (context, idx) {
                              final s = allSurahs[idx];
                              return ListTile(
                                dense: true,
                                leading: Text(
                                  QuranUiUtils.toArabicDigits(s.number),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                title: Text(
                                  'سورة ${s.name}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                subtitle: Text(
                                  'صفحة ${QuranUiUtils.toArabicDigits(repo.getPageForSurah(s.number))}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                trailing: TextButton.icon(
                                  key: ValueKey('play_all_surah_${s.number}'),
                                  icon: const Icon(Icons.play_arrow, size: 14),
                                  label: const Text(
                                    'استماع',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    ref
                                        .read(
                                          adhanAudioControllerProvider.notifier,
                                        )
                                        .playSurah(
                                          surahNumber: s.number,
                                          surahName: s.name,
                                        );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textDark,
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
      isActive: pageNumber == _activePage,
      isDark: isDark,
      onZoomChanged: (zoomed) {
        if (!mounted) return;
        if (pageNumber != _activePage) return;
        if (_isZoomed != zoomed) {
          setState(() {
            _isZoomed = zoomed;
          });
        }
      },
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
  final bool isActive;
  final bool isDark;
  final ValueChanged<bool>? onZoomChanged;

  const _MushafImageSheet({
    super.key,
    required this.repo,
    required this.pageNumber,
    this.isActive = true,
    required this.isDark,
    this.onZoomChanged,
  });

  @override
  State<_MushafImageSheet> createState() => _MushafImageSheetState();
}

class _MushafImageSheetState extends State<_MushafImageSheet> {
  final TransformationController _transformationController =
      TransformationController();
  bool _isZoomed = false;
  bool _suppressTransformCallback = false;
  int _retryKey = 0;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformationChanged);
  }

  void _onTransformationChanged() {
    if (_suppressTransformCallback) return;
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      if (mounted) {
        setState(() {
          _isZoomed = zoomed;
        });
      }
      if (widget.isActive && mounted) {
        widget.onZoomChanged?.call(zoomed);
      }
    }
  }

  void _resetZoom({bool notify = true}) {
    if (!notify) {
      _suppressTransformCallback = true;
      _transformationController.value = Matrix4.identity();
      _suppressTransformCallback = false;
      _isZoomed = false;
    } else {
      _transformationController.value = Matrix4.identity();
    }
  }

  void _toggleZoom() {
    if (_isZoomed) {
      _resetZoom();
    } else {
      _transformationController.value = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
    }
  }

  @override
  void didUpdateWidget(covariant _MushafImageSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageNumber != widget.pageNumber ||
        (oldWidget.isActive && !widget.isActive)) {
      _resetZoom(notify: false);
    }
  }

  @override
  void dispose() {
    _suppressTransformCallback = true;
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
    final primarySurahTitle = surahs.length > 1
        ? surahNames
        : (surahs.isNotEmpty ? 'سورة ${surahs.first.name}' : '');
    final juzNumber = verses.isNotEmpty ? verses.first.juzNumber : 1;
    final isDark = widget.isDark;

    final assetPath = KfqcMushafCatalog.assetPathForPage(widget.pageNumber);

    final semanticLabel =
        'صفحة مصورة رقم ${QuranUiUtils.toArabicDigits(widget.pageNumber)} من مصحف المدينة النبوية، $primarySurahTitle، الجزء ${QuranUiUtils.toArabicDigits(juzNumber)}';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: isDark
              ? const [Color(0xFF17271F), Color(0xFF111A15), Color(0xFF2A281C)]
              : const [Color(0xFFFCF8EA), Color(0xFFEDF3EB), Color(0xFFF6ECD5)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Prominent Page Header Badge (Surah, Juz, and prominent page number)
          // Reserved dynamic layout space outside Expanded image viewport
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
            child: Container(
              key: ValueKey('mushaf_metadata_badge_${widget.pageNumber}'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  const SizedBox(width: 8),
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
                        color: isDark ? Colors.white : AppColors.forestPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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

          // Main Interactive Image Viewer inside clipped Expanded viewport
          Expanded(
            child: ClipRect(
              key: ValueKey('mushaf_image_viewport_${widget.pageNumber}'),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: GestureDetector(
                      onDoubleTap: _toggleZoom,
                      child: InteractiveViewer(
                        key: ValueKey(
                          'mushaf_interactive_viewer_${widget.pageNumber}',
                        ),
                        transformationController: _transformationController,
                        minScale: 1.0,
                        maxScale: 4.0,
                        panEnabled: _isZoomed,
                        clipBehavior: Clip.hardEdge,
                        child: Semantics(
                          image: true,
                          label: semanticLabel,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors
                                  .white, // Genuine white sheet paper; no color inversion in dark mode
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
                              vertical: 4,
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
                                            'يرجى إعادة المحاولة لتحميل صورة الصفحة.',
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
                                            icon: const Icon(
                                              Icons.refresh,
                                              size: 16,
                                            ),
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
            ),
          ),
        ],
      ),
    );
  }
}
