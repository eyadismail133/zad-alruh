import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المصادر والخصوصية'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Privacy Commitment Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.privacy_tip_outlined, color: AppColors.forestPrimary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'سياسة الخصوصية والبيانات',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'تطبيق زاد الروح مجاني بالكامل وبدون إعلانات وبدون تتبع. لا يتطلب التطبيق إنشاء حساب أو تسجيل دخول، وتُحفظ كافة بيانات القراءة والختم والعدادات محلياً على ذاكرة جهازك فقط دون رفعها إلى أي خوادم خارجية.\n\nقد يطلب التطبيق مستقبلاً إذن الموقع الجغرافي اختيارياً لحساب مواقيت الصلاة واتجاه القبلة محلياً دون إرسال الإحداثيات لخوادم خارجية.\n\nنظراً للاقتصار على الحفظ المحلي، فإن حذف التطبيق أو تغيير الجهاز لا يضمن استعادة سجلاتك السابقة.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Sources and Attribution Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.source_outlined, color: AppColors.goldAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'مصادر المحتوى والتراخيص',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildSourceItem(
                      title: 'القرآن الكريم (النص والرسم)',
                      detail: 'النص العثماني من مشروع تنزيل (Tanzil Uthmani v1.1) برخصته الأصلية؛ معالجة وضبط العرض البرمجي قيد الإتمام. صفحات مصحف المدينة المنورة (٦٠٤ صفحات) قيد المراجعة وتدقيق التراخيص.',
                      isDark: isDark,
                    ),
                    const Divider(height: 16),
                    _buildSourceItem(
                      title: 'الأحاديث النبوية الشريفة',
                      detail: 'موسوعة الأحاديث النبوية (HadeethEnc) كمصدر أولي للأحاديث وشروحها؛ تخريج ومراجعة المحتوى قيد التدقيق الشرعي قبل إدراجه.',
                      isDark: isDark,
                    ),
                    const Divider(height: 16),
                    _buildSourceItem(
                      title: 'الأذكار والأدعية',
                      detail: 'مستندة إلى نصوص حصن المسلم المعتمدة؛ ضبط الأعداد وصيغ الأدعية وتدقيق إسنادها قيد المراجعة والتجهيز.',
                      isDark: isDark,
                    ),
                    const Divider(height: 16),
                    _buildSourceItem(
                      title: 'الخطوط والطباعة',
                      detail: 'خط IBM Plex Sans Arabic (حقوق النسخ © 2017 IBM Corp. مع حفظ اسم الخط "Plex"، رخصة SIL OFL 1.1) وخط Amiri Quran (حقوق النسخ 2010-2022 The Amiri Project Authors، رخصة SIL OFL 1.1).',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            Center(
              child: Text(
                'زاد الروح · الإصدار ٠.١.٠',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.darkTextMuted : AppColors.textSubtle,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceItem({
    required String title,
    required String detail,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          detail,
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
