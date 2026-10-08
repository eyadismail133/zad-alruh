/// Verified Quran audio metadata and URL conventions for MP3Quran streaming.
///
/// Verified 2026-10-07 from official MP3Quran developer catalog:
/// - Reciter ID 123: مشاري العفاسي (Mishary Al-Afasy)
/// - Moshaf ID 123: حفص عن عاصم - مرتل (Hafs 'an 'Asim - Murattal)
/// - Riwayah ID 1, complete 114 chapters (1..114)
/// - HTTPS CDN Server: https://cdn.mp3quran.net/audio/mishary-alafasy/r1/
/// - Exact padded 3-digit filename convention: 001.mp3 through 114.mp3
/// - Permissions: https://www.mp3quran.net/ar/privacy (rights section 66)
class QuranAudioSource {
  static const String reciterName = 'مشاري العفاسي';
  static const String riwayahName = 'حفص عن عاصم - مرتل';
  static const int reciterId = 123;
  static const int moshafId = 123;
  static const int riwayahId = 1;
  static const int surahTotal = 114;

  static const String serverBaseUrl =
      'https://cdn.mp3quran.net/audio/mishary-alafasy/r1/';

  static const String websiteUrl = 'https://www.mp3quran.net';
  static const String privacyPolicyUrl =
      'https://www.mp3quran.net/ar/privacy';
  static const String apiUrl = 'https://www.mp3quran.net/ar/api';

  /// Builds the validated HTTPS padded 3-digit URL for surah (1..114).
  ///
  /// Throws [ArgumentError] if [surahNumber] is outside the 1..114 range.
  static String getSurahAudioUrl(int surahNumber) {
    if (surahNumber < 1 || surahNumber > surahTotal) {
      throw ArgumentError.value(
        surahNumber,
        'surahNumber',
        'رقم السورة يجب أن يكون بين ١ و $surahTotal',
      );
    }
    final padded = surahNumber.toString().padLeft(3, '0');
    return '$serverBaseUrl$padded.mp3';
  }
}
