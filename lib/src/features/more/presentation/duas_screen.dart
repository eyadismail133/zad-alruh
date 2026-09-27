import 'package:flutter/material.dart';
import '../../../core/widgets/empty_state_view.dart';

class DuasScreen extends StatelessWidget {
  const DuasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأدعية المأثورة'),
      ),
      body: const SafeArea(
        child: EmptyStateView(
          icon: Icons.menu_book_rounded,
          statusTag: 'قيد التدقيق والتوثيق',
          title: 'مجموعة الأدعية قيد التدقيق والتوثيق',
          message:
              'التزاماً بنزاهة المحتوى الشرعي، لا يتضمن التطبيق أدعية تجريبية أو مولدة آلياً. سيتم إدراج نصوص الأدعية المأثورة من طبعة حصن المسلم المعتمدة ومراجعتها بدقة قبل الإطلاق.',
        ),
      ),
    );
  }
}
