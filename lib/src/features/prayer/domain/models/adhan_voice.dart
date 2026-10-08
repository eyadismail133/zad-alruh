import 'package:flutter/foundation.dart';

@immutable
class AdhanVoice {
  final String id;
  final bool isFajr;
  final String nameAr;
  final String title;
  final String performerOrSource;
  final String license;
  final String licenseUrl;
  final String sourceUrl;
  final String audioAssetPath;
  final String alertClipPath;
  final int durationSeconds;

  const AdhanVoice({
    required this.id,
    required this.isFajr,
    required this.nameAr,
    required this.title,
    required this.performerOrSource,
    required this.license,
    required this.licenseUrl,
    required this.sourceUrl,
    required this.audioAssetPath,
    required this.alertClipPath,
    required this.durationSeconds,
  });

  static const AdhanVoice adam = AdhanVoice(
    id: 'adam',
    isFajr: false,
    nameAr: 'أذان (تسجيل عام)',
    title: 'Beautiful adhan',
    performerOrSource: 'Adam-synagda',
    license: 'Creative Commons CC0 1.0 Universal',
    licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
    sourceUrl: 'https://commons.wikimedia.org/wiki/File:Beautiful_adhan.ogg',
    audioAssetPath: 'assets/audio/adhan/adam-converted.mp3',
    alertClipPath: 'assets/audio/adhan/adam-alert.wav',
    durationSeconds: 154,
  );

  static const AdhanVoice atcovi = AdhanVoice(
    id: 'atcovi',
    isFajr: false,
    nameAr: 'أذان (المصدر: Atcovi)',
    title: 'The Adhan - Muslim Call to Prayer - Aaqib Azeez',
    performerOrSource: 'Atcovi',
    license:
        'Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)',
    licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
    sourceUrl:
        'https://commons.wikimedia.org/wiki/File:The_Adhan_-_Muslim_Call_to_Prayer_-_Aaqib_Azeez.mp3',
    audioAssetPath: 'assets/audio/adhan/atcovi-original.mp3',
    alertClipPath: 'assets/audio/adhan/atcovi-alert.wav',
    durationSeconds: 87,
  );

  static const AdhanVoice malmoFajr = AdhanVoice(
    id: 'malmo_fajr',
    isFajr: true,
    nameAr: 'أذان الفجر - المركز الإسلامي في مالمو',
    title: 'Eid al-Fitr Fajr azan at Malmö Mosque - 19 August 2012',
    performerOrSource: 'المركز الإسلامي في مالمو (Islamic Center Malmö)',
    license: 'Creative Commons Attribution 3.0 Unported (CC BY 3.0)',
    licenseUrl: 'https://creativecommons.org/licenses/by/3.0/',
    sourceUrl:
        'https://commons.wikimedia.org/wiki/File:Eid_al-Fitr_Fajr_azan_at_Malm%C3%B6_Mosque_-_19_August_2012.webm',
    audioAssetPath: 'assets/audio/adhan/malmo-fajr-extracted.mp3',
    alertClipPath: 'assets/audio/adhan/malmo-fajr-alert.wav',
    durationSeconds: 248,
  );

  static const List<AdhanVoice> allVoices = [adam, atcovi, malmoFajr];
  static const List<AdhanVoice> generalVoices = [adam, atcovi];
  static const List<AdhanVoice> fajrVoices = [adam, atcovi, malmoFajr];

  static AdhanVoice? findById(String id) {
    for (final voice in allVoices) {
      if (voice.id == id) return voice;
    }
    return null;
  }

  static AdhanVoice getFallbackGeneral() => adam;
  static AdhanVoice getFallbackFajr() => malmoFajr;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdhanVoice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AdhanVoice(id: $id, name: $nameAr, fajr: $isFajr)';
}
