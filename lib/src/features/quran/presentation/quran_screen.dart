import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../progress/presentation/controllers/progress_controller.dart';

class QuranScreen extends ConsumerStatefulWidget {
  const QuranScreen({super.key});

  @override
  ConsumerState<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends ConsumerState<QuranScreen> {
  void _showAddBookmarkDialog(int currentPage) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _AddBookmarkDialog(currentPage: currentPage, ref: ref),
    );
  }

  Future<void> _deleteBookmark(BuildContext context, int id) async {
    try {
      await ref.read(bookmarksControllerProvider.notifier).deleteBookmark(id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('تعذر حذف العلامة: $e'),
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

  Future<void> _savePage(BuildContext context, int page) async {
    try {
      await ref.read(readingProgressControllerProvider.notifier).savePage(page);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('تعذر حفظ موضع القراءة: $e'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () => _savePage(context, page),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final readingAsync = ref.watch(readingProgressControllerProvider);
    final bookmarksAsync = ref.watch(bookmarksControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('القرآن الكريم'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'إضافة علامة',
            onPressed: () {
              final currentPage = readingAsync.valueOrNull?.lastPage ?? 1;
              _showAddBookmarkDialog(currentPage);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: readingAsync.when(
          data: (reading) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Active Reading State Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
                      ),
                    ),
                    child: Column(
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Text(
                              'موضع القراءة المحفوظ',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.amber.withAlpha(40) : AppColors.goldSoftTint,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'صفحة ${reading.lastPage} / ٦٠٤',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppColors.darkGoldAccent : AppColors.goldDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            IconButton.outlined(
                              icon: const Icon(Icons.arrow_forward_ios, size: 16),
                              tooltip: 'الصفحة السابقة',
                              onPressed: reading.lastPage > 1
                                  ? () => _savePage(context, reading.lastPage - 1)
                                  : null,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                'صفحة ${reading.lastPage}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppColors.darkTextPrimary : AppColors.forestPrimary,
                                ),
                              ),
                            ),
                            IconButton.outlined(
                              icon: const Icon(Icons.arrow_back_ios, size: 16),
                              tooltip: 'الصفحة التالية',
                              onPressed: reading.lastPage < 604
                                  ? () => _savePage(context, reading.lastPage + 1)
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Honest Empty State Banner
                  const EmptyStateView(
                    icon: Icons.menu_book,
                    statusTag: 'قيد التدقيق والترخيص المعتمد',
                    title: 'المصحف الشريف قيد التدقيق والترخيص',
                    message:
                        'التزاماً بنزاهة المحتوى الديني، لا يحتوي هذا الإصدار على نصوص أو صور تجريبية. سيتم إدراج ٦٠٤ صفحات من مصحف المدينة المنورة ونصوص التنزيل العثماني الموثقة بالكامل بعد انتهاء الفحص والترخيص المعتمد.',
                  ),

                  const SizedBox(height: 16),

                  // Persisted Bookmarks Section
                  Text(
                    'العلامات المرجعية المحفوظة',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),

                  bookmarksAsync.when(
                    data: (bookmarks) {
                      if (bookmarks.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'لا توجد علامات محفوظة حالياً. انقر على أيقونة الإضافة لحفظ موضعك.',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                              ),
                            ),
                          ),
                        );
                      }
                      return Column(
                        children: bookmarks.map((b) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.bookmark, color: AppColors.goldAccent),
                              title: Text(
                                b.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              subtitle: Text('صفحة ${b.pageNumber} من ٦٠٤', style: const TextStyle(fontSize: 10)),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: b.id != null
                                    ? () => _deleteBookmark(context, b.id!)
                                    : null,
                              ),
                              onTap: () => _savePage(context, b.pageNumber),
                            ),
                          );
                        }).toList(),
                      );
                    },
                    loading: () => const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
                    error: (err, _) => RetryableErrorView(
                      message: err.toString(),
                      onRetry: () => ref.read(bookmarksControllerProvider.notifier).retry(),
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => RetryableErrorView(
            message: err.toString(),
            onRetry: () => ref.read(readingProgressControllerProvider.notifier).retry(),
          ),
        ),
      ),
    );
  }
}

class _AddBookmarkDialog extends StatefulWidget {
  final int currentPage;
  final WidgetRef ref;

  const _AddBookmarkDialog({
    required this.currentPage,
    required this.ref,
  });

  @override
  State<_AddBookmarkDialog> createState() => _AddBookmarkDialogState();
}

class _AddBookmarkDialogState extends State<_AddBookmarkDialog> {
  late final TextEditingController _controller;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: 'علامة صفحة ${widget.currentPage}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.ref.read(bookmarksControllerProvider.notifier).addBookmark(
            name: name,
            pageNumber: widget.currentPage,
          );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر حفظ العلامة: $e. يرجى المحاولة مجدداً.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة علامة مرجعية'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'اسم العلامة',
              border: OutlineInputBorder(),
            ),
            enabled: !_isLoading,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 11),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
    );
  }
}
