/// Immutable metadata describing the bundled HadeethEnc corpus.
class HadithMetadata {
  final String source;
  final String downloadUrl;
  final String checkUrl;
  final String edition;
  final String version;
  final String lastUpdate;
  final String language;
  final String selectionGrade;
  final int totalRecords;
  final String? rawA1Block;

  const HadithMetadata({
    required this.source,
    required this.downloadUrl,
    required this.checkUrl,
    required this.edition,
    required this.version,
    required this.lastUpdate,
    required this.language,
    required this.selectionGrade,
    required this.totalRecords,
    this.rawA1Block,
  });

  factory HadithMetadata.fromJson(Map<String, dynamic> json) {
    return HadithMetadata(
      source: json['source'] as String? ?? 'https://hadeethenc.com/ar',
      downloadUrl:
          json['download_url'] as String? ??
          'https://hadeethenc.com/browse/download/ar',
      checkUrl:
          json['check_url'] as String? ??
          'https://hadeethenc.com/en/check/ar/v1.7.0',
      edition:
          json['edition'] as String? ??
          'HadeethEnc Arabic v1.7.0 (2025-11-12)',
      version: json['version'] as String? ?? 'v1.7.0',
      lastUpdate: json['last_update'] as String? ?? '2025-11-12 00:00:55',
      language: json['language'] as String? ?? 'العربية',
      selectionGrade: json['selection_grade'] as String? ?? 'صحيح',
      totalRecords: json['total_records'] as int? ?? 3213,
      rawA1Block: json['raw_a1_block'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'source': source,
      'download_url': downloadUrl,
      'check_url': checkUrl,
      'edition': edition,
      'version': version,
      'last_update': lastUpdate,
      'language': language,
      'selection_grade': selectionGrade,
      'total_records': totalRecords,
      if (rawA1Block != null) 'raw_a1_block': rawA1Block,
    };
  }
}
