/// Immutable domain model representing a single Prophetic Hadith record
/// from HadeethEnc (Encyclopedia of Prophetic Hadiths).
class HadithItem {
  /// Unique Hadith identifier from HadeethEnc.
  final int id;

  /// Original Hadith title / summary.
  final String title;

  /// Full original verbatim Hadith text (including Sanad and Matn).
  final String hadithText;

  /// Verbatim scholarly explanation (شرح الحديث).
  final String explanation;

  /// Verbatim vocabulary / word meanings (معاني الكلمات).
  final String wordMeanings;

  /// Verbatim deduced benefits and rulings (الفوائد المستنبطة).
  final String benefits;

  /// Authenticity grade from source (e.g. "صحيح").
  final String grade;

  /// Scholarly source takhrij / citation (e.g. "متفق عليه", "رواه البخاري").
  final String takhrij;

  /// Direct link to the Hadith record on HadeethEnc portal.
  final String link;

  const HadithItem({
    required this.id,
    required this.title,
    required this.hadithText,
    required this.explanation,
    required this.wordMeanings,
    required this.benefits,
    required this.grade,
    required this.takhrij,
    required this.link,
  });

  factory HadithItem.fromJson(Map<String, dynamic> json) {
    return HadithItem(
      id: json['id'] is int ? json['id'] as int : int.parse(json['id'].toString()),
      title: json['title'] as String? ?? '',
      hadithText: json['hadith_text'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      wordMeanings: json['word_meanings'] as String? ?? '',
      benefits: json['benefits'] as String? ?? '',
      grade: json['grade'] as String? ?? '',
      takhrij: json['takhrij'] as String? ?? '',
      link: json['link'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'hadith_text': hadithText,
      'explanation': explanation,
      'word_meanings': wordMeanings,
      'benefits': benefits,
      'grade': grade,
      'takhrij': takhrij,
      'link': link,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HadithItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'HadithItem(id: $id, title: $title, grade: $grade)';
}
