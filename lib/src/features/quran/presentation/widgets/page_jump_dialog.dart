import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../utils/quran_ui_utils.dart';

/// Modal dialog allowing user to jump to any page between 1 and 604.
///
/// Accepts both ASCII digits (0-9) and Arabic-Indic digits (٠-٩) after UI normalization.
class PageJumpDialog extends StatefulWidget {
  final int initialPage;

  const PageJumpDialog({super.key, required this.initialPage});

  static Future<int?> show(BuildContext context, {required int initialPage}) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => PageJumpDialog(initialPage: initialPage),
    );
  }

  @override
  State<PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<PageJumpDialog> {
  late final TextEditingController _controller;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPage.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final page = QuranUiUtils.normalizeAndParsePageNumber(_controller.text);
    if (page == null) {
      setState(() {
        _errorMessage = 'يرجى إدخال رقم صفحة صحيح بين ١ و ٦٠٤';
      });
      return;
    }
    Navigator.of(context).pop(page);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.menu_book_outlined,
            color: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
            size: 22,
          ),
          const SizedBox(width: 8),
          const Flexible(child: Text('الانتقال إلى صفحة')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'أدخل رقم الصفحة في مصحف المدينة (من ١ إلى ٦٠٤):',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'مثال: ٤٢ أو 42',
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
                suffixText: '/ ٦٠٤',
              ),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() {
                    _errorMessage = null;
                  });
                }
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('انتقال')),
      ],
    );
  }
}
