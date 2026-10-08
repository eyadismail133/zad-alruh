import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../hisn/domain/models/hisn_item.dart';
import '../../hisn/domain/repositories/hisn_repository.dart';
import '../../hisn/presentation/controllers/hisn_provider.dart';
import '../../hisn/presentation/hisn_chapter_screen.dart';
import '../../hisn/presentation/hisn_detail_screen.dart';

/// Screen providing responsive Arabic RTL browsing, search, and navigation for
/// the complete Hisn al-Muslim (حصن المسلم من أذكار الكتاب والسنة) corpus.
class DuasScreen extends ConsumerStatefulWidget {
  final HisnRepository? repository;
  final int? initialChapterNumber;

  const DuasScreen({
    super.key,
    this.repository,
    this.initialChapterNumber,
  });

  @override
  ConsumerState<DuasScreen> createState() => _DuasScreenState();
}

class _DuasScreenState extends ConsumerState<DuasScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedTabIndex = 0; // 0: Chapters (132), 1: All Items (267)
  bool _hasNavigatedToInitialChapter = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialChapterNumber != null) {
      _selectedTabIndex = 0;
      if (widget.repository != null) {
        _navigateToInitialChapterIfNeeded(widget.repository!);
      }
    }
  }

  void _navigateToInitialChapterIfNeeded(HisnRepository repo) {
    if (_hasNavigatedToInitialChapter) return;
    final initial = widget.initialChapterNumber;
    if (initial == null) return;
    final chapter = repo.getChapter(initial);
    if (chapter == null) return;

    _hasNavigatedToInitialChapter = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => HisnChapterScreen(
              chapter: chapter,
              repository: repo,
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
    });
  }

  String _formatRepeatLabel(int target) {
    if (target == 1) return 'مرة واحدة';
    if (target == 2) return 'مرتان';
    if (target >= 3 && target <= 10) return '$target مرات';
    return '$target مرة';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Use injected repository if provided (e.g. for testing), otherwise watch Riverpod provider
    if (widget.repository != null) {
      final repo = widget.repository!;
      if (widget.initialChapterNumber != null &&
          repo.getChapter(widget.initialChapterNumber!) != null) {
        _navigateToInitialChapterIfNeeded(repo);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('الأدعية والأذكار (حصن المسلم)'),
            ),
            body: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
        );
      }
      return _buildContent(context, repo, isDark);
    }

    ref.listen<AsyncValue<HisnRepository>>(
      hisnRepositoryProvider,
      (previous, next) {
        next.whenData(_navigateToInitialChapterIfNeeded);
      },
    );

    final hisnAsync = ref.watch(hisnRepositoryProvider);

    return hisnAsync.when(
      loading: () => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('الأدعية والأذكار (حصن المسلم)'),
          ),
          body: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'جاري قراءة أذكار حصن المسلم الموثقة...',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
      error: (err, stack) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('الأدعية والأذكار (حصن المسلم)'),
          ),
          body: SafeArea(
            child: RetryableErrorView(
              message:
                  'تعذر تحميل أذكار حصن المسلم من ملف الحزمة المحلي. يُرجى إعادة المحاولة.',
              onRetry: () => ref.refresh(hisnRepositoryProvider),
            ),
          ),
        ),
      ),
      data: (repo) {
        if (widget.initialChapterNumber != null &&
            repo.getChapter(widget.initialChapterNumber!) != null) {
          _navigateToInitialChapterIfNeeded(repo);
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('الأدعية والأذكار (حصن المسلم)'),
              ),
              body: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }
        return _buildContent(context, repo, isDark);
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    HisnRepository repo,
    bool isDark,
  ) {
    final isSearching = _searchQuery.trim().isNotEmpty;
    final searchResults = isSearching ? repo.search(_searchQuery) : const <HisnItem>[];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الأدعية والأذكار (حصن المسلم)'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // 1. Search Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'ابحث في نصوص الأذكار أو أسماء الأبواب أو رقم الذكر...',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.textMuted,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: _clearSearch,
                            tooltip: 'مسح البحث',
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF1B2420)
                        : const Color(0xFFF4F6F2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppColors.darkCardBorder
                            : const Color(0xFFD8E2DA),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppColors.darkCardBorder
                            : const Color(0xFFD8E2DA),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.forestPrimary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),

              // 2. Tab selector (when not searching)
              if (!isSearching) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<int>(
                          segments: [
                            ButtonSegment<int>(
                              value: 0,
                              label: Text(
                                'الأبواب والفصول (${repo.chaptersCount})',
                                style: const TextStyle(fontSize: 12),
                              ),
                              icon: const Icon(Icons.folder_open_rounded, size: 16),
                            ),
                            ButtonSegment<int>(
                              value: 1,
                              label: Text(
                                'جميع الأذكار (${repo.count})',
                                style: const TextStyle(fontSize: 12),
                              ),
                              icon: const Icon(Icons.menu_book_rounded, size: 16),
                            ),
                          ],
                          selected: {_selectedTabIndex},
                          onSelectionChanged: (newSelection) {
                            setState(() {
                              _selectedTabIndex = newSelection.first;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Search count header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'نتائج البحث في حصن المسلم',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.forestPrimary,
                          ),
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
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${searchResults.length} من ${repo.count}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.forestPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Divider(height: 12),

              // 3. Body View: Search Results, Chapters List, or All Items List
              Expanded(
                child: isSearching
                    ? _buildSearchResultsList(searchResults, repo, isDark)
                    : (_selectedTabIndex == 0
                        ? _buildChaptersList(repo, isDark)
                        : _buildAllItemsList(repo, isDark)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultsList(
    List<HisnItem> results,
    HisnRepository repo,
    bool isDark,
  ) {
    if (results.isEmpty) {
      return const Center(
        child: EmptyStateView(
          icon: Icons.search_off_rounded,
          title: 'لم يتم العثور على أذكار تطابق بحثك',
          message:
              'جرّب البحث بكلمات أخرى، أو بجزء من نص الذكر أو عنوان الباب أو رقم الذكر.',
        ),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemBuilder: (context, index) {
        final item = results[index];
        return _buildItemCard(item, isDark);
      },
    );
  }

  Widget _buildChaptersList(HisnRepository repo, bool isDark) {
    final chapters = repo.allChapters;

    return ListView.builder(
      itemCount: chapters.length,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: isDark
                  ? AppColors.darkCardBorder
                  : AppColors.forestSoftTint,
              child: Text(
                '${chapter.number}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkGoldAccent
                      : AppColors.forestPrimary,
                ),
              ),
            ),
            title: Text(
              chapter.title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.textDark,
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkCardBorder
                    : AppColors.forestSoftTint,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${chapter.itemsCount} ${chapter.itemsCount == 1 ? 'ذكر' : 'أذكار'}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkGoldAccent
                      : AppColors.forestPrimary,
                ),
              ),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => HisnChapterScreen(
                    chapter: chapter,
                    repository: repo,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAllItemsList(HisnRepository repo, bool isDark) {
    final items = repo.allItems;

    return ListView.builder(
      itemCount: items.length,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildItemCard(item, isDark);
      },
    );
  }

  Widget _buildItemCard(HisnItem item, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => HisnDetailScreen(item: item),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${item.chapterNumber}. ${item.chapterTitle}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkGoldAccent
                            : AppColors.forestPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkCardBorder
                          : AppColors.forestSoftTint,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'ذكر #${item.number}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkGoldAccent
                            : AppColors.forestPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Body preview
              Text(
                item.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontFamily: 'Amiri Quran',
                  height: 1.8,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              // Footer row: Repeat badge & Footnotes count
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (item.repeatTarget != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.amber.shade900.withAlpha(50)
                            : const Color(0xFFFFF9E6),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isDark
                              ? Colors.amber.shade700
                              : AppColors.goldAccent,
                        ),
                      ),
                      child: Text(
                        'التكرار: ${_formatRepeatLabel(item.repeatTarget!)}',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkGoldAccent
                              : Colors.brown.shade800,
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    children: [
                      Text(
                        '${item.footnotes.length} مراجع',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_left_rounded,
                        size: 16,
                        color: isDark
                            ? AppColors.darkTextMuted
                            : AppColors.textMuted,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
