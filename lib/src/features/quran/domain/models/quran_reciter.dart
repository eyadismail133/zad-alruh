import 'package:flutter/foundation.dart';

/// A full-Quran (114 surahs) Hafs 'an 'Asim murattal recitation hosted on the
/// MP3Quran CDN.
///
/// Server URLs verified 2026-11-08 against the official MP3Quran catalog
/// https://mp3quran.net/api/v3/reciters?language=ar (each entry: moshaf
/// "حفص عن عاصم - مرتل", surah_total 114). File naming: 001.mp3 … 114.mp3.
@immutable
class QuranReciter {
  final String id;
  final String nameAr;
  final int reciterId;
  final int moshafId;
  final String serverBaseUrl;

  const QuranReciter({
    required this.id,
    required this.nameAr,
    required this.reciterId,
    required this.moshafId,
    required this.serverBaseUrl,
  });

  static const String riwayahName = 'حفص عن عاصم - مرتل';

  String surahUrl(int surahNumber) {
    if (surahNumber < 1 || surahNumber > 114) {
      throw ArgumentError.value(
        surahNumber,
        'surahNumber',
        'رقم السورة يجب أن يكون بين ١ و ١١٤',
      );
    }
    return '$serverBaseUrl${surahNumber.toString().padLeft(3, '0')}.mp3';
  }

  static const QuranReciter alafasy = QuranReciter(
    id: 'alafasy',
    nameAr: 'مشاري العفاسي',
    reciterId: 123,
    moshafId: 123,
    serverBaseUrl: 'https://cdn.mp3quran.net/audio/mishary-alafasy/r1/',
  );

  static const List<QuranReciter> all = [
    alafasy,
    QuranReciter(
      id: 'abdulbasit',
      nameAr: 'عبد الباسط عبد الصمد',
      reciterId: 51,
      moshafId: 53,
      serverBaseUrl:
          'https://cdn.mp3quran.net/audio/abdulbasit-abdulsamad/r3/',
    ),
    QuranReciter(
      id: 'husary',
      nameAr: 'محمود خليل الحصري',
      reciterId: 118,
      moshafId: 118,
      serverBaseUrl: 'https://cdn.mp3quran.net/audio/mahmoud-husary/r1/',
    ),
    QuranReciter(
      id: 'minshawi',
      nameAr: 'محمد صديق المنشاوي',
      reciterId: 112,
      moshafId: 112,
      serverBaseUrl: 'https://cdn.mp3quran.net/audio/muhammad-minshawi/r1/',
    ),
    QuranReciter(
      id: 'sudais',
      nameAr: 'عبد الرحمن السديس',
      reciterId: 54,
      moshafId: 54,
      serverBaseUrl: 'https://cdn.mp3quran.net/audio/abdulrahman-sudais/r1/',
    ),
    QuranReciter(
      id: 'shuraim',
      nameAr: 'سعود الشريم',
      reciterId: 31,
      moshafId: 31,
      serverBaseUrl: 'https://cdn.mp3quran.net/audio/saud-shuraim/r1/',
    ),
    QuranReciter(
      id: 'maher',
      nameAr: 'ماهر المعيقلي',
      reciterId: 102,
      moshafId: 102,
      serverBaseUrl: 'https://cdn.mp3quran.net/audio/maher-muaiqly/r1/',
    ),
    QuranReciter(
      id: 'ghamdi',
      nameAr: 'سعد الغامدي',
      reciterId: 30,
      moshafId: 30,
      serverBaseUrl: 'https://cdn.mp3quran.net/audio/saad-ghamdi/r1/',
    ),
    QuranReciter(
      id: 'dosari',
      nameAr: 'ياسر الدوسري',
      reciterId: 92,
      moshafId: 92,
      serverBaseUrl: 'https://cdn.mp3quran.net/audio/yasser-dosari/r1/',
    ),
    QuranReciter(
      id: 'qatami',
      nameAr: 'ناصر القطامي',
      reciterId: 86,
      moshafId: 86,
      serverBaseUrl: 'https://cdn.mp3quran.net/audio/nasser-qatami/r1/',
    ),
    QuranReciter(
      id: 'ajmi',
      nameAr: 'أحمد بن علي العجمي',
      reciterId: 5,
      moshafId: 5,
      serverBaseUrl: 'https://cdn.mp3quran.net/audio/ahmad-ajmi/r1/',
    ),
  ];

  static QuranReciter byId(String? id) {
    for (final r in all) {
      if (r.id == id) return r;
    }
    return alafasy;
  }
}
