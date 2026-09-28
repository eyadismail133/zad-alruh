import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';

class _LoadedLicenses {
  final String tanzilCopyright;
  final String ibmPlexLicense;
  final String amiriLicense;

  const _LoadedLicenses({
    required this.tanzilCopyright,
    required this.ibmPlexLicense,
    required this.amiriLicense,
  });
}

class SourcesScreen extends StatefulWidget {
  final AssetBundle? bundle;

  const SourcesScreen({super.key, this.bundle});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  Future<_LoadedLicenses>? _licensesFuture;
  AssetBundle? _lastBundle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = widget.bundle ?? DefaultAssetBundle.of(context);
    if (_licensesFuture == null || _lastBundle != bundle) {
      _lastBundle = bundle;
      _licensesFuture = _loadLicenses(bundle);
    }
  }

  static Future<_LoadedLicenses> _loadLicenses(AssetBundle bundle) async {
    final quranText = await bundle.loadString(
      'assets/content/quran/quran-uthmani.txt',
      cache: false,
    );
    final lines = quranText.split('\n');
    final tanzil = lines
        .where((l) => l.trim().startsWith('#'))
        .join('\n')
        .trim();

    final plex = (await bundle.loadString(
      'assets/fonts/IBM-Plex-LICENSE.txt',
      cache: false,
    )).trim();

    final amiri = (await bundle.loadString(
      'assets/fonts/Amiri-OFL.txt',
      cache: false,
    )).trim();

    return _LoadedLicenses(
      tanzilCopyright: tanzil,
      ibmPlexLicense: plex,
      amiriLicense: amiri,
    );
  }

  Future<void> _copyLink(BuildContext context, String url, String label) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم نسخ رابط $label بنجاح: $url'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('تعذر نسخ رابط $label إلى الحافظة.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _openUrl(BuildContext context, String url, String label) async {
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        _showLaunchFallback(context, url, label);
      }
    } on PlatformException catch (_) {
      if (context.mounted) {
        _showLaunchFallback(context, url, label);
      }
    } catch (_) {
      if (context.mounted) {
        _showLaunchFallback(context, url, label);
      }
    }
  }

  void _showLaunchFallback(BuildContext context, String url, String label) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade800,
        content: Text('تعذر فتح رابط $label في المتصفح الخارجي.'),
        action: SnackBarAction(
          label: 'نسخ الرابط',
          textColor: Colors.white,
          onPressed: () => _copyLink(context, url, label),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('المصادر والخصوصية والتراخيص')),
      body: SafeArea(
        child: FutureBuilder<_LoadedLicenses>(
          future: _licensesFuture,
          builder: (context, snapshot) {
            final licenses = snapshot.data;

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. Local-Only Privacy Commitment Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.privacy_tip_outlined,
                              color: AppColors.forestPrimary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'سياسة الخصوصية المحلية (بدون تتبع)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'تطبيق زاد الروح مجاني بالكامل وبدون إعلانات وبدون تتبع أو تحليلات عن بُعد. لا يتطلب التطبيق إنشاء حساب أو تسجيل دخول، وتُحفظ كافة بيانات القراءة والعلامات المرجعية والتقدم اليومي محلياً على ذاكرة جهازك فقط في قاعدة بيانات SQLite محلية دون مزامنة سحابية ودون إرسالها إلى أي خوادم خارجية.\n\nنظراً للاقتصار على الحفظ المحلي المستقل، فإن حذف التطبيق أو تغيير الجهاز يؤدي إلى فقدان السجلات المحلية السابقة.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.6,
                            color: isDark
                                ? AppColors.darkTextMuted
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // 2. Verified Local Content Status Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.verified_outlined,
                              color: AppColors.forestPrimary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'حالة المحتوى المدمج والمحلي',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildContentStatusItem(
                          title: 'النص القرآني الكريم (رسم عثماني)',
                          status: 'مدمج وموثق بالكامل',
                          isBundled: true,
                          detail:
                              'نص القرآن الكريم كاملاً برواية حفص عن عاصم مدمج محلياً من مشروع تنزيل (Tanzil.net) الإصدار ١.١ بعد التحقق من مطابقته وبصمته الرقمية.',
                          isDark: isDark,
                        ),
                        const Divider(height: 16),
                        _buildContentStatusItem(
                          title: 'بيانات السور والأجزاء وصفحات المصحف',
                          status: 'مدمجة ومحققة',
                          isBundled: true,
                          detail:
                              'فهارس ١١٤ سورة و٣٠ جزءاً و٦٠٤ صفحات مع أسماء السور ومواضع النزول من بيانات تنزيل المحققة.',
                          isDark: isDark,
                        ),
                        const Divider(height: 16),
                        _buildContentStatusItem(
                          title: 'موسوعة الأحاديث النبوية (٣٢١٣ حديثاً صحيحاً)',
                          status: 'مدمج ومتحقق من سلامة المصدر',
                          isBundled: true,
                          detail:
                              '٣٢١٣ حديثاً نبوياً صحيحاً مدمجة محلياً بالكامل من موسوعة الأحاديث النبوية (HadeethEnc.com) الإصدار ١.٧.٠ مع التحقق البرمجي التام من سلامة المصدر والتخريج، والمراجعة الشرعية البشرية قيد الإجراء.',
                          isDark: isDark,
                        ),
                        const Divider(height: 16),
                        _buildContentStatusItem(
                          title: 'صفحات المصحف المصورة (٦٠٤ صفحات)',
                          status: 'قيد الاعتماد والترخيص',
                          isBundled: false,
                          detail:
                              'الصور عالية الدقة لصفحات مصحف المدينة المنورة قيد التدقيق القانوني والترخيص الدقيق لضمان سلامة المصدر والخط، ويتوفر حالياً وضع القراءة النصية الكامل الموثق.',
                          isDark: isDark,
                        ),
                        const Divider(height: 16),
                        _buildContentStatusItem(
                          title: 'التسجيلات الصوتية والتلاوات',
                          status: 'قيد المراجعة والاعتماد',
                          isBundled: false,
                          detail:
                              'لا يحتوي الإصدار الحالي على تلاوات صوتية أو أزرار تشغيل تلاوة غير محققة محلياً، لحين تدقيق رخص التلاوات.',
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // 3. Technical Offline Guarantee Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.wifi_off_outlined,
                              color: AppColors.forestPrimary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'العمل دون اتصال بالإنترنت (Offline-First)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'يعمل التطبيق بشكل كامل دون الحاجة لأي اتصال بالإنترنت، ولا يطلب صلاحية الوصول للشبكة لتشغيل وظائف القرآن والبحث والأذكار. التصفح والبحث واستعراض العلامات كلها تجري محلياً ١٠٠٪ دون أي اعتماد على خوادم أو واجهات برمجية خارجية.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.6,
                            color: isDark
                                ? AppColors.darkTextMuted
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // 4. Tanzil Attribution & Verbatim Original License (or honest error/loading state)
                if (snapshot.connectionState == ConnectionState.waiting) ...[
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text(
                              'جاري قراءة نصوص التراخيص الأصلية من حزمة التطبيق...',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ] else if (snapshot.hasError || licenses == null) ...[
                  _buildErrorCard(context, isDark),
                ] else ...[
                  ..._buildLoadedLicensesCards(context, licenses, isDark),
                ],

                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'زاد الروح · تطبيق إسلامي بدون خوادم أو تتبع · الإصدار ٠.١.٠',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.textSubtle,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.amber, size: 36),
            const SizedBox(height: 10),
            const Text(
              'تعذر قراءة نصوص التراخيص الأصلية من ملفات الحزمة.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('إعادة المحاولة'),
              onPressed: () {
                setState(() {
                  final bundle =
                      widget.bundle ?? DefaultAssetBundle.of(context);
                  _licensesFuture = _loadLicenses(bundle);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLoadedLicensesCards(
    BuildContext context,
    _LoadedLicenses licenses,
    bool isDark,
  ) {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.menu_book, color: AppColors.forestPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'نسب المصدر ورخصة نص تنزيل (Tanzil License)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'المصدر: مشروع تنزيل (Tanzil Project)\nرابط المشروع: https://tanzil.net\nرابط رخصة النص: https://tanzil.net/docs/Text_License',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.open_in_browser, size: 12),
                    label: const Text(
                      'زيارة موقع تنزيل',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () =>
                        _openUrl(context, 'https://tanzil.net', 'مشروع تنزيل'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 12),
                    label: const Text(
                      'نسخ رابط تنزيل',
                      style: TextStyle(fontSize: 10),
                    ),
                    onPressed: () =>
                        _copyLink(context, 'https://tanzil.net', 'مشروع تنزيل'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 12),
                    label: const Text(
                      'نسخ رابط الرخصة',
                      style: TextStyle(fontSize: 10),
                    ),
                    onPressed: () => _copyLink(
                      context,
                      'https://tanzil.net/docs/Text_License',
                      'رخصة نص تنزيل',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'النقر على زيارة الموقع يفتح متصفح جهازك الخارجي بناءً على طلبك فقط. يعمل التطبيق بدون اتصال بالإنترنت بالكامل.',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'النص الحرفي المقروء لكتلة حقوق ورخصة التنزيل الأصلية من الملف المدمج:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkGoldAccent
                      : AppColors.forestMedium,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF161E1A)
                      : const Color(0xFFF7F8F4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkCardBorder
                        : const Color(0xFFD8E2DA),
                  ),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    licenses.tanzilCopyright,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10,
                      height: 1.45,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.teal.shade900.withAlpha(40)
                      : const Color(0xFFEFF5F0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.teal.shade700
                        : AppColors.forestLight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إشعار إسناد رخصة المشاع الإبداعي (Creative Commons 3.0):',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkGoldAccent
                            : AppColors.forestPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'نص القرآن الكريم مأخوذ من مشروع تنزيل (Tanzil.net) بموجب رخصة Creative Commons Attribution 3.0 (تنزيل، الإصدار ١.١). لم يتم إدخال أي تعديل أو تحريف على النص القرآني المعتمد والمدمج محلياً، وهو مطابق للنص الأصلي حرفاً بحرف.',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.5,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      // 5. Fonts & Metadata Licenses Card
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.font_download_outlined,
                    color: AppColors.forestPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تراخيص الخطوط وبيانات المصحف الوصفية',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'بيانات السور والأجزاء والتسلسل الوصفي للمصحف:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkGoldAccent
                      : AppColors.forestMedium,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'المصدر: بيانات مشروع تنزيل (Tanzil.info / Tanzil.net)\nالترخيص: رخصة المشاع الإبداعي بنسب المصنف (Creative Commons Attribution - unspecified cc-by version)\nالاستخدام: فهرسة وتحديد مواضع السور والأجزاء والصفحات ومطابقتها نصياً دون تعديل.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.copyright,
                    size: 16,
                    color: AppColors.forestPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تراخيص الخطوط المعتمدة (SIL OFL 1.1)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildFontLicenseItem(
                fontName: 'خط IBM Plex Sans Arabic',
                licenseText: licenses.ibmPlexLicense,
                isDark: isDark,
              ),
              const Divider(height: 16),
              _buildFontLicenseItem(
                fontName: 'خط Amiri Quran (الخط القرآني)',
                licenseText: licenses.amiriLicense,
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      // 6. HadeethEnc Attribution & Licensing Card
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.format_quote_rounded,
                    color: AppColors.forestPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'نسب المصدر ورخصة موسوعة الأحاديث النبوية (HadeethEnc)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'المصدر: موسوعة الأحاديث النبوية (HadeethEnc.com)\nالإصدار المعتمد: v1.7.0 (تاريخ التحديث: 2025-11-12)\nرابط البوابة: https://hadeethenc.com/ar\nرابط فحص التحديثات: https://hadeethenc.com/en/check/ar/v1.7.0\nرابط التنزيل المباشر: https://hadeethenc.com/browse/download/ar',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.open_in_browser, size: 12),
                    label: const Text(
                      'زيارة موقع الموسوعة',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _openUrl(
                      context,
                      'https://hadeethenc.com/ar',
                      'موسوعة الأحاديث النبوية',
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 12),
                    label: const Text(
                      'نسخ رابط الموسوعة',
                      style: TextStyle(fontSize: 10),
                    ),
                    onPressed: () => _copyLink(
                      context,
                      'https://hadeethenc.com/ar',
                      'موسوعة الأحاديث النبوية',
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 12),
                    label: const Text(
                      'نسخ رابط التحقق',
                      style: TextStyle(fontSize: 10),
                    ),
                    onPressed: () => _copyLink(
                      context,
                      'https://hadeethenc.com/en/check/ar/v1.7.0',
                      'رابط التحقق من التحديثات',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.teal.shade900.withAlpha(40)
                      : const Color(0xFFEFF5F0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.teal.shade700
                        : AppColors.forestLight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إشعار إسناد وشروط إعادة النشر (HadeethEnc Terms):',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkGoldAccent
                            : AppColors.forestPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'يلتزم التطبيق التزاماً تاماً بضوابط النقل الحرفي والأمانة العلمية وشروط الاستخدام وإعادة النشر المعتمدة لدى موسوعة الأحاديث النبوية (HadeethEnc.com): تم نقل وتبويب النصوص والتخريج والشروح كما وردت في الموسوعة دون أي تعديل أو تحريف أو توليد آلي، مع بيان التخريج ودرجة الصحة المعتمدة في الموسوعة وبيانات الإصدار، وخلو التطبيق تماماً من الإعلانات التجارية. لا يدّعي التطبيق أي اعتماد شرعي أو تحقيق علمي مستقل.',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.5,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildContentStatusItem({
    required String title,
    required String status,
    required bool isBundled,
    required String detail,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textDark,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isBundled
                    ? (isDark
                          ? Colors.teal.shade900.withAlpha(50)
                          : AppColors.forestSoftTint)
                    : (isDark
                          ? Colors.amber.shade900.withAlpha(40)
                          : AppColors.goldSoftTint),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isBundled
                      ? (isDark
                            ? Colors.tealAccent.shade100
                            : AppColors.forestPrimary)
                      : (isDark
                            ? AppColors.darkGoldAccent
                            : AppColors.goldDark),
                ),
              ),
            ),
          ],
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

  Widget _buildFontLicenseItem({
    required String fontName,
    required String licenseText,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fontName,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161E1A) : const Color(0xFFF7F8F4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? AppColors.darkCardBorder
                  : const Color(0xFFD8E2DA),
            ),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              licenseText,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 9.5,
                height: 1.4,
              ),
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      ],
    );
  }
}
