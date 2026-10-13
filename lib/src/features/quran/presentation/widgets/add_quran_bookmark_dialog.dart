import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../progress/presentation/controllers/progress_controller.dart';
import '../../domain/models/verse.dart';
import 'page_verse_selector.dart';

/// Modal dialog for creating a named bookmark with optional exact verse reference.
///
/// Ensures inputs are preserved upon write failure and prevents duplicate rapid submissions.
class AddQuranBookmarkDialog extends ConsumerStatefulWidget {
  final int currentPage;
  final List<Verse> versesOnPage;
  final Verse? initialVerse;

  const AddQuranBookmarkDialog({
    super.key,
    required this.currentPage,
    required this.versesOnPage,
    this.initialVerse,
  });

  static Future<bool?> show(
    BuildContext context, {
    required int currentPage,
    required List<Verse> versesOnPage,
    Verse? initialVerse,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AddQuranBookmarkDialog(
        currentPage: currentPage,
        versesOnPage: versesOnPage,
        initialVerse: initialVerse,
      ),
    );
  }

  @override
  ConsumerState<AddQuranBookmarkDialog> createState() =>
      _AddQuranBookmarkDialogState();
}

class _AddQuranBookmarkDialogState
    extends ConsumerState<AddQuranBookmarkDialog> {
  late final TextEditingController _nameController;
  Verse? _selectedVerse;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedVerse = widget.versesOnPage
        .where(
          (v) =>
              v.pageNumber == widget.currentPage &&
              v.id == widget.initialVerse?.id,
        )
        .firstOrNull;
    final defaultName = widget.initialVerse != null
        ? 'علامة آية ${widget.initialVerse!.verseNumber} - صفحة ${widget.currentPage}'
        : 'علامة صفحة ${widget.currentPage}';
    _nameController = TextEditingController(text: defaultName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return; // Prevent duplicate rapid clicks

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال اسم للعلامة المرجعية';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(bookmarksControllerProvider.notifier)
          .addBookmark(
            name: name,
            pageNumber: widget.currentPage,
            surahNumber: _selectedVerse?.surahNumber,
            verseNumber: _selectedVerse?.verseNumber,
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر حفظ العلامة المرجعية. يرجى المحاولة مجدداً.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.bookmark_add,
            color: isDark ? AppColors.darkGoldAccent : AppColors.goldAccent,
            size: 22,
          ),
          const SizedBox(width: 8),
          const Flexible(child: Text('إضافة علامة مرجعية')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'اسم العلامة:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                hintText: 'اسم العلامة المرجعية',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'الآية المرتبطة (اختياري من الصفحة الحالية):',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            if (widget.versesOnPage.isNotEmpty)
              IgnorePointer(
                ignoring: _isLoading,
                child: PageVerseSelector(
                  verses: widget.versesOnPage,
                  initialVerse: _selectedVerse,
                  allowWholePage: true,
                  onChanged: (value) => setState(() => _selectedVerse = value),
                ),
              ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade700),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.red.shade200 : Colors.red.shade900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('حفظ العلامة'),
        ),
      ],
    );
  }
}
