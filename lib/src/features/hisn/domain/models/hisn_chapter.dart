/// Immutable domain model representing a chapter / section in Hisn al-Muslim.
class HisnChapter {
  /// 1-indexed chapter number (1..132).
  final int number;

  /// Verbatim chapter title in Arabic.
  final String title;

  /// Number of dhikr/dua items in this chapter.
  final int itemsCount;

  /// Ordered list of item IDs (1..267) belonging to this chapter.
  final List<int> itemIds;

  const HisnChapter({
    required this.number,
    required this.title,
    required this.itemsCount,
    required this.itemIds,
  });

  factory HisnChapter.fromJson(Map<String, dynamic> json) {
    final rawItemIds = json['item_ids'] as List<dynamic>? ?? [];
    final itemIds = rawItemIds
        .map((e) => e is int ? e : int.parse(e.toString()))
        .toList(growable: false);

    return HisnChapter(
      number: json['number'] is int
          ? json['number'] as int
          : int.parse(json['number'].toString()),
      title: json['title'] as String? ?? '',
      itemsCount: json['items_count'] is int
          ? json['items_count'] as int
          : int.parse(json['items_count'].toString()),
      itemIds: itemIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'number': number,
    'title': title,
    'items_count': itemsCount,
    'item_ids': itemIds,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HisnChapter && runtimeType == other.runtimeType && number == other.number;

  @override
  int get hashCode => number.hashCode;

  @override
  String toString() => 'HisnChapter(number: $number, title: $title, count: $itemsCount)';
}
