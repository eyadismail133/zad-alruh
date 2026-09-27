import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'duas_screen.dart';
import 'favorites_screen.dart';
import 'hadith_screen.dart';
import 'settings_screen.dart';
import 'sources_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المزيد'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // App Branding Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCardBorder : AppColors.forestSoftTint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/branding/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.auto_stories,
                        color: AppColors.forestPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'زادُ الروح',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'رفيقك اليومي للعبادة والطمأنينة',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Navigation Sections
            Card(
              child: Column(
                children: [
                  _buildNavTile(
                    context,
                    icon: Icons.settings_outlined,
                    title: 'الإعدادات',
                    subtitle: 'المظهر، حجم الخط، المدينة، وإعادة الضبط',
                    destination: const SettingsScreen(),
                  ),
                  const Divider(height: 1),
                  _buildNavTile(
                    context,
                    icon: Icons.menu_book_rounded,
                    title: 'الأدعية',
                    subtitle: 'أدعية مأثورة من القرآن والسنة',
                    destination: const DuasScreen(),
                  ),
                  const Divider(height: 1),
                  _buildNavTile(
                    context,
                    icon: Icons.format_quote_rounded,
                    title: 'الأحاديث النبوية',
                    subtitle: 'مختارات من صحيح الأحاديث النبوية',
                    destination: const HadithScreen(),
                  ),
                  const Divider(height: 1),
                  _buildNavTile(
                    context,
                    icon: Icons.favorite_border_rounded,
                    title: 'المفضلة والعلامات',
                    subtitle: 'العلامات المرجعية والأدعية المحفوظة',
                    destination: const FavoritesScreen(),
                  ),
                  const Divider(height: 1),
                  _buildNavTile(
                    context,
                    icon: Icons.info_outline_rounded,
                    title: 'المصادر والخصوصية',
                    subtitle: 'سياسة الخصوصية وتراخيص المحتوى والخطوط',
                    destination: const SourcesScreen(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget destination,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.forestPrimary),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => destination),
        );
      },
    );
  }
}
