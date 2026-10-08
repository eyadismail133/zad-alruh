import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/retryable_error_view.dart';
import '../../../prayer/data/sources/city_asset_adapter.dart';
import '../../../prayer/domain/models/selected_city.dart';
import '../../../prayer/domain/repositories/city_repository.dart';

/// Modal dialog allowing offline search and selection across all 34,149 GeoNames cities.
///
/// Supports:
/// - Arabic diacritic-insensitive search (e.g. القاهرة, مكة, الرياض, القدس).
/// - Latin and ASCII search (e.g. Cairo, London, New York, Istanbul).
/// - Responsive layout down to 320x480 and textScale 2.0.
/// - Returns the chosen [SelectedCity] or null if dismissed.
class CitySearchPickerDialog extends ConsumerStatefulWidget {
  final int? currentCityId;

  const CitySearchPickerDialog({
    super.key,
    this.currentCityId,
  });

  /// Helper static method to show the city picker dialog.
  static Future<SelectedCity?> show(
    BuildContext context, {
    int? currentCityId,
  }) {
    return showDialog<SelectedCity>(
      context: context,
      barrierDismissible: true,
      builder: (_) => CitySearchPickerDialog(currentCityId: currentCityId),
    );
  }

  @override
  ConsumerState<CitySearchPickerDialog> createState() =>
      _CitySearchPickerDialogState();
}

class _CitySearchPickerDialogState
    extends ConsumerState<CitySearchPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SelectedCity> _getInitialSuggestions(CityRepository repo) {
    // Curated initial prominent global and regional cities when query is empty
    const prominentIds = [
      360630, // Cairo (EG)
      104515, // Makkah (SA)
      109223, // Madinah (SA)
      108410, // Riyadh (SA)
      281184, // Jerusalem (PS)
      292223, // Dubai (AE)
      745044, // Istanbul (TR)
      2643743, // London (GB)
      5128581, // New York City (US)
      1006984, // Alexandria (EG)
    ];

    final list = <SelectedCity>[];
    for (final id in prominentIds) {
      final city = repo.getCityById(id);
      if (city != null) {
        list.add(city);
      }
    }
    return list;
  }

  String _formatPopulation(int pop) {
    if (pop >= 1000000) {
      final m = (pop / 1000000).toStringAsFixed(1);
      return '$m م نسمة';
    } else if (pop >= 1000) {
      final k = (pop / 1000).toStringAsFixed(0);
      return '$k ألف نسمة';
    }
    return '$pop نسمة';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cityRepoAsync = ref.watch(cityRepositoryProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 480,
          maxHeight: 600,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.location_city,
                    color: isDark
                        ? AppColors.darkGoldAccent
                        : AppColors.forestPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'اختر المدينة (قاعدة بيانات المدن العالمية)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'ابحث بالعربية أو بالإنجليزية (مثل: مكة، Cairo)...',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.textMuted,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark
                      ? AppColors.darkSurface
                      : AppColors.forestSoftTint.withAlpha(50),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.darkCardBorder
                          : AppColors.cardBorder,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.darkCardBorder
                          : AppColors.cardBorder,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.darkGoldAccent
                          : AppColors.forestPrimary,
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _query = val.trim();
                  });
                },
              ),
            ),

            const SizedBox(height: 8),

            // Results List / Status
            Expanded(
              child: cityRepoAsync.when(
                data: (repo) {
                  final results = _query.isEmpty
                      ? _getInitialSuggestions(repo)
                      : repo.search(_query, limit: 50);

                  if (results.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 40,
                              color: isDark
                                  ? AppColors.darkTextMuted
                                  : AppColors.textMuted,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'لم يتم العثور على مدينة مطابقة',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'جرّب كتابة الاسم باللغة الإنجليزية أو اسم الدولة',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkTextMuted
                                    : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Scrollbar(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                      ),
                      itemBuilder: (context, index) {
                        final city = results[index];
                        final isSelected = widget.currentCityId == city.id;
                        final displayName = city.arabicName != null
                            ? '${city.arabicName} (${city.name})'
                            : city.name;

                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          tileColor: isSelected
                              ? (isDark
                                  ? AppColors.darkForestPrimary.withAlpha(60)
                                  : AppColors.forestSoftTint)
                              : null,
                          title: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isSelected
                                  ? (isDark
                                      ? AppColors.darkGoldAccent
                                      : AppColors.forestPrimary)
                                  : (isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textDark),
                            ),
                          ),
                          subtitle: Text(
                            '${city.countryCode} · ${city.timezone} · ${_formatPopulation(city.population)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? AppColors.darkTextMuted
                                  : AppColors.textMuted,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: isDark
                                      ? AppColors.darkGoldAccent
                                      : AppColors.forestPrimary,
                                )
                              : const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                          onTap: () {
                            Navigator.of(context).pop(city);
                          },
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: RetryableErrorView(
                      message: 'تعذر تحميل قاعدة بيانات المدن.',
                      onRetry: () => ref.invalidate(cityRepositoryProvider),
                    ),
                  ),
                ),
              ),
            ),

            // Footer info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'قاعدة البيانات المحلية تحتوي على ٣٤,١٤٩ مدينة بدون اتصال بالإنترنت.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? AppColors.darkTextMuted
                      : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
