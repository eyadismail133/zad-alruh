import 'package:flutter/material.dart';
import '../../../core/widgets/empty_state_view.dart';

class HadithScreen extends StatelessWidget {
  const HadithScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأحاديث الشريفة'),
      ),
      body: const SafeArea(
        child: EmptyStateView(
          icon: Icons.format_quote_rounded,
          statusTag: 'قيد التدقيق والتحقيق',
          title: 'مجموعة الأحاديث قيد التدقيق الشرعي',
          message:
              'وفقاً لمعايير النزاهة الشرعية، سيتم توفير ١٠٠ حديث نبوي صحيح معتمد من موسوعة الأحاديث النبوية (HadeethEnc) مع أرقام الأبواب والتخريج والمراجعة البشرية المؤهلة. لا تُستخدم أية نصوص تجريبية في النسخة الحالية.',
        ),
      ),
    );
  }
}
