import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/models/selected_city.dart';
import 'geonames_source_verifier.dart';

/// Utilities for normalizing search text across Arabic and Latin scripts without altering source bytes.
class CitySearchNormalizer {
  CitySearchNormalizer._();

  static final RegExp _tashkeelRegex = RegExp(r'[\u064B-\u065F\u0670]');
  static final RegExp _alefRegex = RegExp(r'[إأآٱ]');
  static final RegExp _tatweelRegex = RegExp(r'\u0640');
  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static final RegExp _arabicCharRegex = RegExp(r'[\u0600-\u06FF]');

  /// Checks whether a given string contains Arabic characters.
  static bool hasArabic(String text) => _arabicCharRegex.hasMatch(text);

  /// Normalizes Arabic text by stripping diacritics, unifying Alef variants,
  /// normalizing Taa Marbuta and Alef Maksura, and removing tatweel.
  /// If [removeSpaces] is true, strips all whitespace (e.g. 'نيو يورك' -> 'نيويورك').
  static String normalizeArabic(String text, {bool removeSpaces = false}) {
    var s = text.replaceAll(_tashkeelRegex, '');
    s = s.replaceAll(_alefRegex, 'ا');
    s = s.replaceAll('ة', 'ه');
    s = s.replaceAll('ى', 'ي');
    s = s.replaceAll(_tatweelRegex, '');
    if (removeSpaces) {
      s = s.replaceAll(_whitespaceRegex, '');
    } else {
      s = s.replaceAll(_whitespaceRegex, ' ').trim();
    }
    return s.toLowerCase();
  }

  /// Normalizes Latin search text: lowercased, trimmed, and collapsed spaces.
  static String normalizeLatin(String text) {
    return text.trim().toLowerCase().replaceAll(_whitespaceRegex, ' ');
  }
}

/// Pure Dart parser for the GeoNames cities15000 tab-separated data file.
class GeoNamesParser {
  GeoNamesParser._();

  static bool _timeZonesInitialized = false;

  static void _ensureTimeZones() {
    if (!_timeZonesInitialized) {
      tzdata.initializeTimeZones();
      _timeZonesInitialized = true;
    }
  }

  /// Parses the full contents of `cities15000.txt` into a validated list of [SelectedCity] objects.
  ///
  /// Throws [GeoNamesValidationException] if any row fails validation.
  static List<SelectedCity> parse(
    String content, {
    bool validateTimezones = true,
  }) {
    if (validateTimezones) {
      _ensureTimeZones();
    }

    final lines = content.split('\n');
    final cities = <SelectedCity>[];
    final seenIds = <int>{};

    int lineNumber = 0;
    for (final line in lines) {
      lineNumber++;
      if (line.isEmpty || line.trim().isEmpty) continue;

      final fields = line.split('\t');
      if (fields.length != 19) {
        throw GeoNamesValidationException(
          'Line $lineNumber: expected 19 tab-separated fields, got ${fields.length}',
        );
      }

      // Field 0: geonameid
      final id = int.tryParse(fields[0]);
      if (id == null || id <= 0) {
        throw GeoNamesValidationException(
          'Line $lineNumber: invalid geonameid "${fields[0]}"',
        );
      }
      if (!seenIds.add(id)) {
        throw GeoNamesValidationException(
          'Line $lineNumber: duplicate geonameid $id',
        );
      }

      // Field 1: name
      final name = fields[1].trim();
      if (name.isEmpty) {
        throw GeoNamesValidationException(
          'Line $lineNumber: city name is empty',
        );
      }

      // Field 2: asciiname
      final asciiName = fields[2].trim();

      // Field 3: alternatenames (comma separated)
      final rawAliases = fields[3].split(',');
      final aliases = <String>[];
      String? primaryArabic;

      for (final raw in rawAliases) {
        final a = raw.trim();
        if (a.isEmpty) continue;
        aliases.add(a);
        if (primaryArabic == null && CitySearchNormalizer.hasArabic(a)) {
          primaryArabic = a;
        }
      }

      // If the primary name itself is Arabic, set it as primary Arabic name
      if (CitySearchNormalizer.hasArabic(name)) {
        primaryArabic ??= name;
      }

      // Field 4: latitude
      final latitude = double.tryParse(fields[4]);
      if (latitude == null ||
          !latitude.isFinite ||
          latitude < -90.0 ||
          latitude > 90.0) {
        throw GeoNamesValidationException(
          'Line $lineNumber: invalid latitude "${fields[4]}" for city $id ($name)',
        );
      }

      // Field 5: longitude
      final longitude = double.tryParse(fields[5]);
      if (longitude == null ||
          !longitude.isFinite ||
          longitude < -180.0 ||
          longitude > 180.0) {
        throw GeoNamesValidationException(
          'Line $lineNumber: invalid longitude "${fields[5]}" for city $id ($name)',
        );
      }

      // Field 8: country code (ISO-3166 2-letter)
      final countryCode = fields[8].trim().toUpperCase();

      // Field 14: population
      final population = int.tryParse(fields[14]) ?? 0;

      // Field 17: timezone
      final timezone = fields[17].trim();
      if (validateTimezones) {
        try {
          tz.getLocation(timezone);
        } on tz.LocationNotFoundException {
          throw GeoNamesValidationException(
            'Line $lineNumber: unknown or unsupported IANA timezone "$timezone" for city $id ($name)',
          );
        }
      }

      cities.add(
        SelectedCity(
          id: id,
          name: name,
          asciiName: asciiName,
          arabicName: primaryArabic,
          countryCode: countryCode,
          latitude: latitude,
          longitude: longitude,
          timezone: timezone,
          population: population,
          aliases: List.unmodifiable(aliases),
        ),
      );
    }

    return List.unmodifiable(cities);
  }
}
