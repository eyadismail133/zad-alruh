/// Immutable domain model representing provenance, edition, and structural metadata
/// of the bundled Hisn al-Muslim corpus.
class HisnMetadata {
  final String title;
  final String author;
  final String source;
  final String sourceEn;
  final String apiTerms;
  final String edition;
  final String language;
  final int totalChapters;
  final int totalItems;
  final int totalFootnotes;
  final String sourceDocxSha256;
  final String acquisitionDate;

  const HisnMetadata({
    required this.title,
    required this.author,
    required this.source,
    required this.sourceEn,
    required this.apiTerms,
    required this.edition,
    required this.language,
    required this.totalChapters,
    required this.totalItems,
    required this.totalFootnotes,
    required this.sourceDocxSha256,
    required this.acquisitionDate,
  });

  factory HisnMetadata.fromJson(Map<String, dynamic> json) {
    return HisnMetadata(
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      source: json['source'] as String? ?? '',
      sourceEn: json['source_en'] as String? ?? '',
      apiTerms: json['api_terms'] as String? ?? '',
      edition: json['edition'] as String? ?? '',
      language: json['language'] as String? ?? 'العربية',
      totalChapters: json['total_chapters'] is int
          ? json['total_chapters'] as int
          : int.parse(json['total_chapters'].toString()),
      totalItems: json['total_items'] is int
          ? json['total_items'] as int
          : int.parse(json['total_items'].toString()),
      totalFootnotes: json['total_footnotes'] is int
          ? json['total_footnotes'] as int
          : int.parse(json['total_footnotes'].toString()),
      sourceDocxSha256: json['source_docx_sha256'] as String? ?? '',
      acquisitionDate: json['acquisition_date'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'author': author,
    'source': source,
    'source_en': sourceEn,
    'api_terms': apiTerms,
    'edition': edition,
    'language': language,
    'total_chapters': totalChapters,
    'total_items': totalItems,
    'total_footnotes': totalFootnotes,
    'source_docx_sha256': sourceDocxSha256,
    'acquisition_date': acquisitionDate,
  };
}
