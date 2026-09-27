import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../progress/data/models/reading_progress.dart';
import '../../progress/presentation/controllers/progress_controller.dart';
import '../data/quran_repository.dart';
import '../data/sources/quran_asset_loader.dart';
import '../domain/models/juz.dart';
import '../domain/models/surah.dart';
import '../domain/models/verse.dart';
import 'controllers/quran_navigation_controller.dart';
import 'quran_reader_screen.dart';
import 'utils/quran_ui_utils.dart';
import 'widgets/add_quran_bookmark_dialog.dart';
import 'widgets/page_jump_dialog.dart';

class QuranScreen extends ConsumerStatefulWidget {
  const QuranScreen({super.key});

  @override
  ConsumerState<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends ConsumerState<QuranScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openReader(int page) {
    ref.read(quranNavigationProvider.notifier).openReader(page);
  }

  Future<void> _openPageJumpDialog(int currentPage) async {
    final targetPage = await PageJumpDialog.show(
      context,
      initialPage: currentPage,
    );
    if (targetPage != null) {
      _openReader(targetPage);
    }
  }

  Future<void> _deleteBookmark(BuildContext context, int id) async {
    try {
      await ref.read(bookmarksControllerProvider.notifier).deleteBookmark(id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: const Text('تعذر حذف العلامة المرجعية.'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () => _deleteBookmark(context, id),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(quranNavigationProvider);
    final readingAsync = ref.watch(readingProgressControllerProvider);
    final quranAsync = ref.watch(quranRepositoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // When the reader view is open, render QuranReaderScreen
    if (navState.isReaderOpen) {
      return QuranReaderScreen(
        initialPage: navState.currentPage,
        onBack: () => ref.read(quranNavigationProvider.notifier).closeReader(),
      );
    }

    // Otherwise render the Quran Index view
    return Scaffold(
      appBar: AppBar(
        title: const Text('القرآن الكريم'),
        actions: [
          IconButton(
            icon: const Icon(Icons.pin_outlined),
            tooltip: 'الانتقال إلى صفحة',
            onPressed: () {
              final currentPage = readingAsync.valueOrNull?.lastPage ?? 1;
              _openPageJumpDialog(currentPage);
            },
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'إضافة علامة',
            onPressed: () {
              final currentPage = readingAsync.valueOrNull?.lastPage ?? 1;
              final quranRepo = quranAsync.valueOrNull;
              final verses = quranRepo?.getVersesForPage(currentPage) ?? [];
              AddQuranBookmarkDialog.show(
                context,
                currentPage: currentPage,
                versesOnPage: verses,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: quranAsync.when(
          data: (quranRepo) {
            if (_searchQuery.isNotEmpty) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: _buildSearchTextField(context, isDark),
                  ),
                  Expanded(
                    child: _buildSearchResults(
                      context,
                      quranRepo,
                      _searchQuery,
                      isDark,
                    ),
                  ),
                ],
              );
            }

            return NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Search Input Field
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: _buildSearchTextField(context, isDark),
                      ),
                      // Resume / Last Read Position Banner
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: readingAsync.when(
                          data: (reading) => _buildResumeBanner(
                            context,
                            quranRepo,
                            reading,
                            isDark,
                          ),
                          loading: () =>
                              _buildResumeBannerLoading(context, isDark),
                          error: (err, _) => _buildResumeBannerError(
                            context,
                            isDark,
                            onRetry: () =>
                                ref.refresh(readingProgressControllerProvider),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverTabBarDelegate(
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: const [
                        Tab(text: 'السور (١١٤)'),
                        Tab(text: 'الأجزاء (٣٠)'),
                        Tab(text: 'العلامات المحفوظة'),
                      ],
                    ),
                    isDark: isDark,
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  // Surahs List Tab
                  _buildSurahsList(
                    context,
                    quranRepo,
                    readingAsync.valueOrNull,
                    isDark,
                  ),

                  // Juzs List Tab
                  _buildJuzsList(
                    context,
                    quranRepo,
                    readingAsync.valueOrNull,
                    isDark,
                  ),

                  // Bookmarks Tab
                  _buildBookmarksList(context, isDark),
                ],
              ),
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

  Widget _buildSearchTextField(BuildContext context, bool isDark) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'ابحث عن آية أو كلمة في المصحف...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: 14,
        ),
      ),
      onChanged: (val) {
        setState(() {
          _searchQuery = val.trim();
        });
      },
    );
  }

  /// Builds the "Last Read" resume banner with verified loaded data.
  Widget _buildResumeBanner(
    BuildContext context,
    QuranRepository repo,
    ReadingProgress readingProgress,
    bool isDark,
  ) {
    final lastPage = readingProgress.lastPage;
    final selectedSurahNum = readingProgress.selectedSurah;
    final selectedVerseNum = readingProgress.selectedVerse;

    String subtitle;
    if (selectedSurahNum != null && selectedVerseNum != null) {
      final surah = repo.getSurah(selectedSurahNum);
      subtitle =
          'سورة ${surah.name} · الآية ${QuranUiUtils.toArabicDigits(selectedVerseNum)} · صفحة ${QuranUiUtils.toArabicDigits(lastPage)}';
    } else {
      final pageVerses = repo.getVersesForPage(lastPage);
      final surah = repo.getSurah(pageVerses.first.surahNumber);
      subtitle =
          'سورة ${surah.name} · صفحة ${QuranUiUtils.toArabicDigits(lastPage)} من ٦٠٤';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.amber.withAlpha(30)
                  : AppColors.goldSoftTint,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_stories,
              color: isDark ? AppColors.darkGoldAccent : AppColors.goldDark,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'آخر موضع قراءة',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark
                  ? AppColors.darkGoldAccent
                  : AppColors.forestPrimary,
              foregroundColor: isDark ? AppColors.textDark : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              elevation: 0,
            ),
            onPressed: () => _openReader(lastPage),
            child: const Text(
              'متابعة ←',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the loading placeholder for the resume banner while progress bootstraps.
  Widget _buildResumeBannerLoading(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.amber.withAlpha(30)
                  : AppColors.goldSoftTint,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_stories,
              color: isDark ? AppColors.darkGoldAccent : AppColors.goldDark,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'آخر موضع قراءة',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'جاري استرجاع موضع القراءة...',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
    );
  }

  /// Builds the Arabic error state and retry action for the resume banner.
  Widget _buildResumeBannerError(
    BuildContext context,
    bool isDark, {
    required VoidCallback onRetry,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: isDark ? Colors.red.shade300 : Colors.red.shade700,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'تعذر تحميل آخر موضع قراءة.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('إعادة المحاولة', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  /// Builds the offline search results with unmodified verbatim text.
  Widget _buildSearchResults(
    BuildContext context,
    QuranRepository repo,
    String query,
    bool isDark,
  ) {
    final results = repo.search(query);

    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 48,
                color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                'لم يتم العثور على آيات تطابق "$query"',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'تأكد من كتابة الكلمة بدون أخطاء إملائية. البحث لا يتأثر بالتشكيل والهمزات.',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            'نتائج البحث: ${QuranUiUtils.toArabicDigits(results.length)} آية',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkGoldAccent : AppColors.goldDark,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: results.length,
            itemBuilder: (ctx, index) {
              final Verse verse = results[index];
              final Surah surah = repo.getSurah(verse.surahNumber);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => _openReader(verse.pageNumber),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'سورة ${surah.name} · الآية ${QuranUiUtils.toArabicDigits(verse.verseNumber)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkGoldAccent
                                    : AppColors.forestPrimary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkCardBorder
                                    : AppColors.forestSoftTint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'صفحة ${QuranUiUtils.toArabicDigits(verse.pageNumber)}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Unmodified original verbatim Uthmani text in Amiri Quran font
                        Text(
                          verse.text,
                          style: TextStyle(
                            fontFamily: 'Amiri Quran',
                            fontSize: 17,
                            height: 1.8,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : const Color(0xFF1B2921),
                          ),
                          textAlign: TextAlign.justify,
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Builds the list of 114 Quran Surahs.
  Widget _buildSurahsList(
    BuildContext context,
    QuranRepository repo,
    ReadingProgress? readingProgress,
    bool isDark,
  ) {
    final surahs = repo.getSurahs();
    final lastPage = readingProgress?.lastPage ?? 1;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: surahs.length,
      itemBuilder: (ctx, index) {
        final Surah surah = surahs[index];
        final startPage = repo.getPageForSurah(surah.number);
        final surahVerses = repo.getVersesForSurah(surah.number);
        final endPage = surahVerses.last.pageNumber;
        final isCurrentSurah = lastPage >= startPage && lastPage <= endPage;

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          color: isCurrentSurah
              ? (isDark
                    ? AppColors.darkForestPrimary.withAlpha(50)
                    : const Color(0xFFEFF5F0))
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isCurrentSurah
                ? BorderSide(
                    color: isDark
                        ? AppColors.darkForestPrimary
                        : AppColors.forestLight,
                    width: 1.5,
                  )
                : BorderSide.none,
          ),
          child: ListTile(
            dense: true,
            leading: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCurrentSurah
                      ? (isDark
                            ? AppColors.darkGoldAccent
                            : AppColors.forestPrimary)
                      : (isDark
                            ? AppColors.darkCardBorder
                            : AppColors.cardBorder),
                ),
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
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  surah.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (isCurrentSurah) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkGoldAccent
                          : AppColors.goldAccent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'موضعك الحالي',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              '${surah.type == "Meccan" ? "مكية" : "مدنية"} · ${QuranUiUtils.toArabicDigits(surah.versesCount)} آية · صفحة ${QuranUiUtils.toArabicDigits(startPage)}',
              style: const TextStyle(fontSize: 10),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 12),
            onTap: () => _openReader(startPage),
          ),
        );
      },
    );
  }

  /// Builds the list of 30 Quran Juzs.
  Widget _buildJuzsList(
    BuildContext context,
    QuranRepository repo,
    ReadingProgress? readingProgress,
    bool isDark,
  ) {
    final juzs = repo.getJuzs();
    final lastPage = readingProgress?.lastPage ?? 1;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: juzs.length,
      itemBuilder: (ctx, index) {
        final Juz juz = juzs[index];
        final startPage = repo.getPageForJuz(juz.number);
        final Surah startSurah = repo.getSurah(juz.startSurahNumber);

        // Determine if this is the current Juz
        final isCurrentJuz = (index < 29)
            ? (lastPage >= startPage &&
                  lastPage < repo.getPageForJuz(index + 2))
            : (lastPage >= startPage && lastPage <= 604);

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          color: isCurrentJuz
              ? (isDark
                    ? AppColors.darkForestPrimary.withAlpha(50)
                    : const Color(0xFFEFF5F0))
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isCurrentJuz
                ? BorderSide(
                    color: isDark
                        ? AppColors.darkForestPrimary
                        : AppColors.forestLight,
                    width: 1.5,
                  )
                : BorderSide.none,
          ),
          child: ListTile(
            dense: true,
            leading: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCurrentJuz
                      ? (isDark
                            ? AppColors.darkGoldAccent
                            : AppColors.forestPrimary)
                      : (isDark
                            ? AppColors.darkCardBorder
                            : AppColors.cardBorder),
                ),
              ),
              child: Center(
                child: Text(
                  QuranUiUtils.toArabicDigits(juz.number),
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
            title: Row(
              children: [
                Text(
                  'الجزء ${QuranUiUtils.toArabicDigits(juz.number)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (isCurrentJuz) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkGoldAccent
                          : AppColors.goldAccent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'موضعك الحالي',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              'يبدأ من: سورة ${startSurah.name} (آية ${QuranUiUtils.toArabicDigits(juz.startVerseNumber)}) · صفحة ${QuranUiUtils.toArabicDigits(startPage)}',
              style: const TextStyle(fontSize: 10),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 12),
            onTap: () => _openReader(startPage),
          ),
        );
      },
    );
  }

  /// Builds the persisted bookmarks list.
  Widget _buildBookmarksList(BuildContext context, bool isDark) {
    final bookmarksAsync = ref.watch(bookmarksControllerProvider);

    return bookmarksAsync.when(
      data: (bookmarks) {
        if (bookmarks.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 48,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'لا توجد علامات مرجعية محفوظة حالياً',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'يمكنك حفظ موضع أي صفحة أو آية أثناء القراءة للعودة إليها لاحقاً.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: bookmarks.length,
          itemBuilder: (ctx, index) {
            final b = bookmarks[index];
            String refDetail =
                'صفحة ${QuranUiUtils.toArabicDigits(b.pageNumber)} من ٦٠٤';
            if (b.surahNumber != null && b.verseNumber != null) {
              refDetail +=
                  ' · سورة ${b.surahNumber} آية ${QuranUiUtils.toArabicDigits(b.verseNumber!)}';
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: const Icon(
                  Icons.bookmark,
                  color: AppColors.goldAccent,
                ),
                title: Text(
                  b.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(refDetail, style: const TextStyle(fontSize: 10)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'حذف العلامة',
                  onPressed: b.id != null
                      ? () => _deleteBookmark(context, b.id!)
                      : null,
                ),
                onTap: () => _openReader(b.pageNumber),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => RetryableErrorView(
        message: 'تعذر تحميل العلامات المرجعية.',
        onRetry: () => ref.read(bookmarksControllerProvider.notifier).retry(),
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final bool isDark;

  _SliverTabBarDelegate(this.tabBar, {required this.isDark});

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: isDark ? AppColors.darkBackground : AppColors.creamBackground,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar || oldDelegate.isDark != isDark;
  }
}
