import 'package:flutter/foundation.dart';

/// Period for daily Dhikr items.
enum DhikrPeriod {
  morning('morning', 'أذكار الصباح'),
  evening('evening', 'أذكار المساء'),
  shared100('shared_100', 'ذكر الاستغفار اليومي (١٠٠ مرة)');

  final String key;
  final String labelArabic;
  const DhikrPeriod(this.key, this.labelArabic);

  static DhikrPeriod fromKey(String key) {
    switch (key) {
      case 'morning':
        return DhikrPeriod.morning;
      case 'evening':
        return DhikrPeriod.evening;
      case 'shared_100':
        return DhikrPeriod.shared100;
      default:
        throw ArgumentError.value(key, 'key', 'Unknown DhikrPeriod key');
    }
  }
}

/// Links an evening alternative to its verbatim source footnote IDs in Hisn al-Muslim.
/// Does NOT contain authored or rewritten formulas; eventual UI renders verbatim
/// text from [HisnItem.footnotes].
@immutable
class EveningAlternativeNote {
  final int itemId;
  final List<String> footnoteIds;

  const EveningAlternativeNote({
    required this.itemId,
    required this.footnoteIds,
  });
}

/// Authoritative catalog owning the exact selection of Morning and Evening Dhikr
/// items from Chapter 27 (items 75..98) of Hisn al-Muslim, plus Chapter 25 items (66..73)
/// for Post-Prayer Dhikr.
class HisnDailyCatalog {
  HisnDailyCatalog._();

  /// 19 items common to both morning and evening (items 75..92 and 98).
  static const List<int> commonItemIds = <int>[
    75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 98,
  ];

  /// Exactly 22 items for Morning Dhikr: 19 common + 93, 94, 95.
  static const List<int> morningItemIds = <int>[
    75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 98,
  ];

  /// Exactly 20 items for Evening Dhikr: 19 common + 97.
  static const List<int> eveningItemIds = <int>[
    75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 97, 98,
  ];

  /// Optional shared daily 100-times item (Item 96: أستغفر الله وأتوب إليه مائة مرة).
  /// Tracked once separately and strictly excluded from both morning (22) and evening (20) denominators.
  static const int sharedDaily100ItemId = 96;

  /// Total count required for morning completion (strictly 22).
  static const int morningTotalCount = 22;

  /// Total count required for evening completion (strictly 20).
  static const int eveningTotalCount = 20;

  /// Post-prayer Dhikr items from Chapter 25 (exactly 8 entries: items 66..73).
  static const List<int> postPrayerItemIds = <int>[
    66, 67, 68, 69, 70, 71, 72, 73,
  ];

  /// Item 75 preface footnote ID (Hadith of Anas footnote 101).
  static const String item75PrefaceFootnoteId = '101';

  /// Item 92: repeatTarget in source asset is null (10 / 1 conditional alternative).
  /// No invented counter is synthesized.
  static const int item92Id = 92;

  /// Evening alternative notes mapping:
  /// 77 notes 104/105, 78 note 107, 80 note 111, 81 note 113, 89 notes 122/123, 90 note 125.
  static const Map<int, EveningAlternativeNote> eveningAlternativeNotes = <int, EveningAlternativeNote>{
    77: EveningAlternativeNote(itemId: 77, footnoteIds: <String>['104', '105']),
    78: EveningAlternativeNote(itemId: 78, footnoteIds: <String>['107']),
    80: EveningAlternativeNote(itemId: 80, footnoteIds: <String>['111']),
    81: EveningAlternativeNote(itemId: 81, footnoteIds: <String>['113']),
    89: EveningAlternativeNote(itemId: 89, footnoteIds: <String>['122', '123']),
    90: EveningAlternativeNote(itemId: 90, footnoteIds: <String>['125']),
  };

  /// Validates whether [itemId] belongs to the given [period].
  static bool isValidPeriodItem(DhikrPeriod period, int itemId) {
    switch (period) {
      case DhikrPeriod.morning:
        return morningItemIds.contains(itemId);
      case DhikrPeriod.evening:
        return eveningItemIds.contains(itemId);
      case DhikrPeriod.shared100:
        return itemId == sharedDaily100ItemId;
    }
  }

  /// Returns the ordered list of item IDs for [period].
  static List<int> getItemIdsForPeriod(DhikrPeriod period) {
    switch (period) {
      case DhikrPeriod.morning:
        return morningItemIds;
      case DhikrPeriod.evening:
        return eveningItemIds;
      case DhikrPeriod.shared100:
        return const <int>[sharedDaily100ItemId];
    }
  }

  /// Verbatim disclaimer explaining personal recorded reading vs compulsory ritual.
  static const String personalTrackingExplanationArabic =
      'تسجيل قراءة شخصية للمتابعة اليومية، وليس إيجاباً أو توثيقاً شعائرياً ملزماً.';
}
