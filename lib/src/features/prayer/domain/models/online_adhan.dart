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

  const OnlineAdhan({
    required this.id,
    required this.nameAr,
    required this.noteAr,
    required this.url,
  });

  /// File name used for the downloaded copy.
  String get fileName => 'adhan_$id.mp3';

  static const String sourceName = 'Islamic Network (AlAdhan.com)';
  static const String sourcePage = 'https://aladhan.com/download-adhans';

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
  ];

  static OnlineAdhan? byId(String? id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }
}
