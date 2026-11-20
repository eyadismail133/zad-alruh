import 'package:flutter/foundation.dart';

/// An adhan recording that is downloaded once from the Islamic Network
/// (AlAdhan.com) CDN and then played offline by the native prayer alarm.
///
/// Source: https://aladhan.com/download-adhans (verified 2026-11-08).
/// Islamic Network confirmed on their community forum that these files may be
/// bundled/played offline in apps without attribution or redistribution
/// restrictions; we credit them anyway. See docs/sources/ADHAN_AUDIO.md.
@immutable
class OnlineAdhan {
  final String id;
  final String nameAr;
  final String noteAr;
  final String url;

  /// Where the recording is downloaded from (shown as credit in the UI).
  final String source;

  const OnlineAdhan({
    required this.id,
    required this.nameAr,
    required this.noteAr,
    required this.url,
    this.source = sourceName,
  });

  /// File name used for the downloaded copy.
  String get fileName => 'adhan_$id.mp3';

  static const String sourceName = 'Islamic Network (AlAdhan.com)';
  static const String sourcePage = 'https://aladhan.com/download-adhans';

  /// Egyptian and Saudi muezzins, added 2026-11-20 at the owner's request.
  /// Listed as free downloads on https://www.assabile.com/adhan-call-prayer
  /// (egypt, makkah, madinah, saudi-arabia)
  /// (Arabic names as published on ar.assabile.com). The site does not
  /// document recording rights; see docs/sources/ADHAN_AUDIO.md.
  static const String assabileName = 'Assabile.com';
  static const String assabilePage =
      'https://www.assabile.com/adhan-call-prayer';
  static const String _assabileBase =
      'https://media.assabile.com/assabile/adhan_3435370/';

  static const List<OnlineAdhan> all = [
    OnlineAdhan(
      id: 'alafasy_1',
      nameAr: 'مشاري راشد العفاسي',
      noteAr: 'أذان (١)',
      url: 'https://cdn.aladhan.com/audio/adhans/a9.mp3',
    ),
    OnlineAdhan(
      id: 'alafasy_2',
      nameAr: 'مشاري راشد العفاسي',
      noteAr: 'أذان (٢)',
      url: 'https://cdn.aladhan.com/audio/adhans/a7.mp3',
    ),
    OnlineAdhan(
      id: 'alafasy_dubai',
      nameAr: 'مشاري راشد العفاسي',
      noteAr: 'أذان قناة دبي ون',
      url: 'https://cdn.aladhan.com/audio/adhans/a4.mp3',
    ),
    OnlineAdhan(
      id: 'nafees',
      nameAr: 'أحمد النفيس',
      noteAr: 'أذان',
      url: 'https://cdn.aladhan.com/audio/adhans/a1.mp3',
    ),
    OnlineAdhan(
      id: 'ozcan',
      nameAr: 'الحافظ مصطفى أوزجان',
      noteAr: 'أذان تركي (مقام)',
      url: 'https://cdn.aladhan.com/audio/adhans/a2.mp3',
    ),
    OnlineAdhan(
      id: 'zahrani',
      nameAr: 'منصور الزهراني',
      noteAr: 'أذان',
      url: 'https://cdn.aladhan.com/audio/adhans/a11-mansour-al-zahrani.mp3',
    ),
    // ---- Saudi muezzins: Makkah, Madinah and others (Assabile) ----
    OnlineAdhan(
      id: 'sa_ali_mulla_1',
      nameAr: 'علي بن أحمد ملا',
      noteAr: 'مؤذن الحرم المكي (١)',
      url: '${_assabileBase}54944191e2e2.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_ali_mulla_2',
      nameAr: 'علي بن أحمد ملا',
      noteAr: 'مؤذن الحرم المكي (٢)',
      url: '${_assabileBase}a3c148ae770f.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_ali_mulla_3',
      nameAr: 'علي بن أحمد ملا',
      noteAr: 'مؤذن الحرم المكي (٣)',
      url: '${_assabileBase}a4ab138564ce.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_ali_mulla_4',
      nameAr: 'علي بن أحمد ملا',
      noteAr: 'مؤذن الحرم المكي (٤)',
      url: '${_assabileBase}77873f64ead9.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_ali_mulla_5',
      nameAr: 'علي بن أحمد ملا',
      noteAr: 'مؤذن الحرم المكي (٥)',
      url: '${_assabileBase}166d1f7c435a.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_ali_mulla_6',
      nameAr: 'علي بن أحمد ملا',
      noteAr: 'مؤذن الحرم المكي (٦)',
      url: '${_assabileBase}3b44ab2cf844.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_farouk_hadrawi',
      nameAr: 'فاروق عبد الرحمن حضراوي',
      noteAr: 'مؤذن الحرم المكي',
      url: '${_assabileBase}1aadb2df7d5c.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_nayef_feda',
      nameAr: 'نايف صالح فيده',
      noteAr: 'مؤذن الحرم المكي',
      url: '${_assabileBase}7f701468a8dc.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_mohamed_raml',
      nameAr: 'محمد خليل رمل',
      noteAr: 'مؤذن الحرم المكي',
      url: '${_assabileBase}c7ba5fb672b3.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_mohamed_ramadan_saad',
      nameAr: 'محمد رمضان سعد',
      noteAr: 'مكة المكرمة',
      url: '${_assabileBase}e9bb86af0d30.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_haram_makki',
      nameAr: 'الحرم المكي',
      noteAr: 'أذان مكة المكرمة',
      url: '${_assabileBase}518b4e081437.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_essam_bukhari',
      nameAr: 'عصام بخاري',
      noteAr: 'مؤذن المسجد النبوي',
      url: '${_assabileBase}7487fa449eeb.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_haram_madani_1',
      nameAr: 'المسجد النبوي',
      noteAr: 'أذان المدينة المنورة (١)',
      url: '${_assabileBase}b30ca9a3e115.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_haram_madani_2',
      nameAr: 'المسجد النبوي',
      noteAr: 'أذان المدينة المنورة (٢)',
      url: '${_assabileBase}c84496bf1a8c.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_haram_madani_3',
      nameAr: 'المسجد النبوي',
      noteAr: 'أذان المدينة المنورة (٣)',
      url: '${_assabileBase}efc564e3b1d2.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_nasser_alobaid_1',
      nameAr: 'ناصر العبيد',
      noteAr: 'أذان سعودي (١)',
      url: '${_assabileBase}c81e4e141865.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_nasser_alobaid_2',
      nameAr: 'ناصر العبيد',
      noteAr: 'أذان سعودي (٢)',
      url: '${_assabileBase}45299e6a8a68.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_nasser_alobaid_3',
      nameAr: 'ناصر العبيد',
      noteAr: 'أذان سعودي (٣)',
      url: '${_assabileBase}e6ced81e9955.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'sa_hassan_baalul',
      nameAr: 'حسن صلاح بعلول',
      noteAr: 'أذان سعودي',
      url: '${_assabileBase}a031983fa2b6.mp3',
      source: assabileName,
    ),
    // ---- Egyptian muezzins (Assabile) ----
    OnlineAdhan(
      id: 'eg_abdulbasit_1',
      nameAr: 'عبد الباسط عبد الصمد',
      noteAr: 'أذان مصري (١)',
      url: '${_assabileBase}1a014366658c.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_abdulbasit_2',
      nameAr: 'عبد الباسط عبد الصمد',
      noteAr: 'أذان مصري (٢)',
      url: '${_assabileBase}0e56abfb1eb3.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_abdulbasit_3',
      nameAr: 'عبد الباسط عبد الصمد',
      noteAr: 'أذان مصري (٣)',
      url: '${_assabileBase}566852c1d145.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_abdulbasit_4',
      nameAr: 'عبد الباسط عبد الصمد',
      noteAr: 'أذان مصري (٤)',
      url: '${_assabileBase}d336be9b95d7.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_abdulbasit_5',
      nameAr: 'عبد الباسط عبد الصمد',
      noteAr: 'أذان مصري (٥)',
      url: '${_assabileBase}02f1bec971bb.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_abdulbasit_6',
      nameAr: 'عبد الباسط عبد الصمد',
      noteAr: 'أذان مصري (٦)',
      url: '${_assabileBase}1125f640d83b.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_abdulbasit_7',
      nameAr: 'عبد الباسط عبد الصمد',
      noteAr: 'أذان مصري (٧)',
      url: '${_assabileBase}4318b757fd42.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_minshawi',
      nameAr: 'محمد صديق المنشاوي',
      noteAr: 'أذان مصري',
      url: '${_assabileBase}984f3e129c8c.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_husary',
      nameAr: 'محمود خليل الحصري',
      noteAr: 'أذان مصري',
      url: '${_assabileBase}cdb24a4bd658.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_mustafa_ismail',
      nameAr: 'مصطفى إسماعيل',
      noteAr: 'أذان مصري',
      url: '${_assabileBase}dd5f42239b71.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_ismail_alsheikh',
      nameAr: 'إسماعيل الشيخ',
      noteAr: 'أذان مصري',
      url: '${_assabileBase}6734c28f3a2d.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_abdelmoneim_abdelmobdi',
      nameAr: 'عبد المنعم عبد المبدئ',
      noteAr: 'أذان مصري',
      url: '${_assabileBase}c3460e1ab635.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_ahmed_alhaddad',
      nameAr: 'أحمد الحداد',
      noteAr: 'أذان مصري',
      url: '${_assabileBase}f30b7631d625.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_omran_mansour',
      nameAr: 'عمران منصور',
      noteAr: 'أذان مصري',
      url: '${_assabileBase}68b0e4999e85.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_abdullah_aldhahabi',
      nameAr: 'عبد الله الذهبي',
      noteAr: 'أذان مصري',
      url: '${_assabileBase}c2f802f38c47.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_ibrahim_abu_raheeq',
      nameAr: 'إبراهيم جبر أبو رحيق',
      noteAr: 'أذان مصري',
      url: '${_assabileBase}e37acc95ebe1.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_mohamed_hammoud_1',
      nameAr: 'محمد حمود',
      noteAr: 'أذان مصري (١)',
      url: '${_assabileBase}f579c205b4b7.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_mohamed_hammoud_2',
      nameAr: 'محمد حمود',
      noteAr: 'أذان مصري (٢)',
      url: '${_assabileBase}592e8a809f00.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_mahmoud_altoukhi',
      nameAr: 'محمود الطوخي',
      noteAr: 'أذان مصري',
      url: '${_assabileBase}bdf9f3101b4c.mp3',
      source: assabileName,
    ),
    OnlineAdhan(
      id: 'eg_ahmed_ali',
      nameAr: 'أحمد علي',
      noteAr: 'أذان مصري',
      url: '${_assabileBase}f77eba62a35f.mp3',
      source: assabileName,
    ),
  ];

  static OnlineAdhan? byId(String? id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }
}
