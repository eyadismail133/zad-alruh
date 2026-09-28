/// Immutable domain model representing a footnote reference within Hisn al-Muslim.
class HisnFootnote {
  /// The footnote reference identifier from the original source.
  final String id;

  /// Verbatim scholarly citation, reference, or takhrij from the original footnote.
  final String text;

  const HisnFootnote({
    required this.id,
    required this.text,
  });

  factory HisnFootnote.fromJson(Map<String, dynamic> json) {
    return HisnFootnote(
      id: json['id']?.toString() ?? '',
      text: json['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HisnFootnote &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text;

  @override
  int get hashCode => Object.hash(id, text);

  @override
  String toString() => 'HisnFootnote(id: $id, text: $text)';
}

/// Immutable domain model representing a single Dhikr / Dua entry from Hisn al-Muslim
/// (حصن المسلم من أذكار الكتاب والسنة) by Dr. Saeed bin Ali bin Wahf Al-Qahtani.
class HisnItem {
  /// Unique 1-indexed sequential item identifier (1..267).
  final int id;

  /// Original item number within the book (1..267).
  final int number;

  /// Chapter number (1..132) this item belongs to.
  final int chapterNumber;

  /// Verbatim chapter title in Arabic.
  final String chapterTitle;

  /// Verbatim complete Arabic text of the Dhikr / Dua (including all continuation paragraphs).
  final String text;

  /// Individual paragraphs making up the entry in the source document.
  final List<String> paragraphs;

  /// IDs of footnotes linked directly to this item.
  final List<String> footnoteIds;

  /// Resolved footnotes containing full scholarly citations and references.
  final List<HisnFootnote> footnotes;

  /// Explicit, unambiguous repetition count applying to the entire entry (e.g. 3, 10, 33, 100),
  /// or null if the source text does not specify an explicit whole-entry count.
  /// A null value indicates that either no number exists in the source, or any numbers present
  /// are ambiguous, apply only to a sub-part or ritual action, are multi-part (e.g. 33/33/34),
  /// or describe a narrative hadith practice rather than a single whole-entry repetition target.
  final int? repeatTarget;

  const HisnItem({
    required this.id,
    required this.number,
    required this.chapterNumber,
    required this.chapterTitle,
    required this.text,
    required this.paragraphs,
    required this.footnoteIds,
    required this.footnotes,
    this.repeatTarget,
  });

  factory HisnItem.fromJson(Map<String, dynamic> json) {
    final rawFootnotes = json['footnotes'] as List<dynamic>? ?? [];
    final footnotes = rawFootnotes
        .whereType<Map<String, dynamic>>()
        .map(HisnFootnote.fromJson)
        .toList(growable: false);

    final rawFootnoteIds = json['footnote_ids'] as List<dynamic>? ?? [];
    final footnoteIds = rawFootnoteIds.map((e) => e.toString()).toList(growable: false);

    final rawParas = json['paragraphs'] as List<dynamic>? ?? [];
    final paragraphs = rawParas.map((e) => e.toString()).toList(growable: false);

    return HisnItem(
      id: json['id'] is int ? json['id'] as int : int.parse(json['id'].toString()),
      number: json['number'] is int
          ? json['number'] as int
          : int.parse(json['number'].toString()),
      chapterNumber: json['chapter_number'] is int
          ? json['chapter_number'] as int
          : int.parse(json['chapter_number'].toString()),
      chapterTitle: json['chapter_title'] as String? ?? '',
      text: json['text'] as String? ?? '',
      paragraphs: paragraphs,
      footnoteIds: footnoteIds,
      footnotes: footnotes,
      repeatTarget: json['repeat_target'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'chapter_number': chapterNumber,
    'chapter_title': chapterTitle,
    'text': text,
    'paragraphs': paragraphs,
    'footnote_ids': footnoteIds,
    'footnotes': footnotes.map((f) => f.toJson()).toList(),
    'repeat_target': repeatTarget,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HisnItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'HisnItem(id: $id, chapter: $chapterNumber - $chapterTitle, repeat: $repeatTarget)';
}
