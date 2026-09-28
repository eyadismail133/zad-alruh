import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../hadith/domain/models/hadith_item.dart';
import '../../hadith/domain/repositories/hadith_repository.dart';
import '../../hadith/presentation/controllers/hadith_provider.dart';
import '../../hadith/presentation/hadith_detail_screen.dart';

class HadithScreen extends ConsumerStatefulWidget {
  final HadithRepository? repository;

  const HadithScreen({
    super.key,
    this.repository,
  });

  @override
  ConsumerState<HadithScreen> createState() => _HadithScreenState();
}

class _HadithScreenState extends ConsumerState<HadithScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Use injected repository if provided (e.g. for testing), otherwise watch Riverpod provider
    if (widget.repository != null) {
      return _buildContent(context, widget.repository!, isDark);
    }

    final hadithAsync = ref.watch(hadithRepositoryProvider);

    return hadithAsync.when(
      loading: () => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('الأحاديث النبوية الشريفة'),
          ),
          body: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'جاري قراءة الأحاديث النبوية الموثقة...',
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
            title: const Text('الأحاديث النبوية الشريفة'),
          ),
          body: SafeArea(
            child: RetryableErrorView(
              message:
                  'تعذر تحميل بيانات الأحاديث النبوية المحلية من ملف الحزمة. يُرجى إعادة المحاولة.',
              onRetry: () => ref.refresh(hadithRepositoryProvider),
            ),
          ),
        ),
      ),
      data: (repo) => _buildContent(context, repo, isDark),
    );
  }

  Widget _buildContent(
    BuildContext context,
    HadithRepository repo,
    bool isDark,
  ) {
    final items = repo.search(_searchQuery);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الأحاديث النبوية الشريفة'),
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
                    hintText: 'ابحث في نصوص الأحاديث أو العناوين أو التخريج...',
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

              // 2. Info / Results Count Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _searchQuery.trim().isEmpty
                            ? 'موسوعة الأحاديث النبوية (HadeethEnc)'
                            : 'نتائج البحث',
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
                        _searchQuery.trim().isEmpty
                            ? '${repo.count} حديثاً صحيحاً'
                            : '${items.length} من ${repo.count}',
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

              const Divider(height: 12),

              // 3. Lazy List or Empty State
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: EmptyStateView(
                          icon: Icons.search_off_rounded,
                          title: 'لم يتم العثور على أحاديث تطابق بحثك',
                          message:
                              'جرّب البحث بكلمات أخرى أو بجزء من نص الحديث أو اسم الكتاب المخرّج.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _HadithListItemCard(
                            item: item,
                            isDark: isDark,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) =>
                                      HadithDetailScreen(hadith: item),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HadithListItemCard extends StatelessWidget {
  final HadithItem item;
  final bool isDark;
  final VoidCallback onTap;

  const _HadithListItemCard({
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Generate brief excerpt from hadith text
    final textPreview = item.hadithText.length > 120
        ? '${item.hadithText.substring(0, 120)}...'
        : item.hadithText;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: ID and Grade
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
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
                        '#${item.id}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkGoldAccent
                              : AppColors.forestPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                          ? Colors.teal.shade900.withAlpha(50)
                          : AppColors.forestSoftTint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.grade,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.tealAccent.shade100
                            : AppColors.forestPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Title
              Text(
                item.title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textDark,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // Text preview
              Text(
                textPreview,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.6,
                  color: isDark
                      ? AppColors.darkTextMuted
                      : AppColors.textMuted,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Takhrij preview and navigation indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.takhrij,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark
                            ? AppColors.darkGoldAccent
                            : AppColors.forestMedium,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 13,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.textSubtle,
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
