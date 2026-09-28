import 'dart:math' as math;

import '../../domain/models/nearest_city_suggestion.dart';
import '../../domain/models/selected_city.dart';
import '../../domain/repositories/city_repository.dart';
import '../sources/geonames_parser.dart';

/// Pre-indexed searchable representations of a city for efficient lookup.
class _CitySearchIndex {
  final SelectedCity city;
  final String normName;
  final String normAscii;
  final String? normArabicPrimarySpaced;
  final String? normArabicPrimaryNoSpace;
  final List<String> normArabicAliasesSpaced;
  final List<String> normArabicAliasesNoSpace;
  final List<String> normLatinAliases;

  _CitySearchIndex(this.city)
    : normName = CitySearchNormalizer.normalizeLatin(city.name),
      normAscii = CitySearchNormalizer.normalizeLatin(city.asciiName),
      normArabicPrimarySpaced = city.arabicName != null
          ? CitySearchNormalizer.normalizeArabic(
              city.arabicName!,
              removeSpaces: false,
            )
          : null,
      normArabicPrimaryNoSpace = city.arabicName != null
          ? CitySearchNormalizer.normalizeArabic(
              city.arabicName!,
              removeSpaces: true,
            )
          : null,
      normArabicAliasesSpaced = city.aliases
          .where(CitySearchNormalizer.hasArabic)
          .map(
            (a) => CitySearchNormalizer.normalizeArabic(a, removeSpaces: false),
          )
          .toList(),
      normArabicAliasesNoSpace = city.aliases
          .where(CitySearchNormalizer.hasArabic)
          .map(
            (a) => CitySearchNormalizer.normalizeArabic(a, removeSpaces: true),
          )
          .toList(),
      normLatinAliases = city.aliases
          .where((a) => !CitySearchNormalizer.hasArabic(a))
          .map(CitySearchNormalizer.normalizeLatin)
          .toList();
}

/// In-memory implementation of [CityRepository] backed by verified GeoNames data.
class InMemoryCityRepository implements CityRepository {
  final List<SelectedCity> _cities;
  final Map<int, SelectedCity> _byId;
  final List<_CitySearchIndex> _searchIndex;

  InMemoryCityRepository(List<SelectedCity> cities)
    : _cities = List.unmodifiable(cities),
      _byId = {for (final c in cities) c.id: c},
      _searchIndex = cities.map((c) => _CitySearchIndex(c)).toList();

  @override
  SelectedCity get defaultCity {
    final cairo = _byId[360630];
    if (cairo != null) return cairo;
    if (_cities.isEmpty) {
      throw StateError('Cannot retrieve default city: no cities loaded');
    }
    throw StateError(
      'GeoNames repository does not contain canonical Cairo record (ID 360630)',
    );
  }

  @override
  int get totalCitiesCount => _cities.length;

  @override
  SelectedCity? getCityById(int id) => _byId[id];

  @override
  List<SelectedCity> search(String query, {int limit = 50}) {
    if (limit <= 0) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Search limit must be greater than zero',
      );
    }

    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final isArabic = CitySearchNormalizer.hasArabic(trimmed);

    final scored = <(int score, SelectedCity city)>[];

    if (isArabic) {
      final querySpaced = CitySearchNormalizer.normalizeArabic(
        trimmed,
        removeSpaces: false,
      );
      final queryNoSpace = CitySearchNormalizer.normalizeArabic(
        trimmed,
        removeSpaces: true,
      );

      for (final entry in _searchIndex) {
        int bestScore = 0;

        // Check primary Arabic name
        if (entry.normArabicPrimarySpaced != null) {
          final pSpaced = entry.normArabicPrimarySpaced!;
          final pNoSpace = entry.normArabicPrimaryNoSpace!;

          if (pSpaced == querySpaced || pNoSpace == queryNoSpace) {
            bestScore = math.max(bestScore, 100);
          } else if (pSpaced.startsWith(querySpaced) ||
              pNoSpace.startsWith(queryNoSpace)) {
            bestScore = math.max(bestScore, 75);
          } else if (pSpaced.contains(querySpaced) ||
              pNoSpace.contains(queryNoSpace)) {
            bestScore = math.max(bestScore, 50);
          }
        }

        // Check Arabic aliases
        for (int i = 0; i < entry.normArabicAliasesSpaced.length; i++) {
          final aSpaced = entry.normArabicAliasesSpaced[i];
          final aNoSpace = entry.normArabicAliasesNoSpace[i];

          if (aSpaced == querySpaced || aNoSpace == queryNoSpace) {
            bestScore = math.max(bestScore, 100);
          } else if (aSpaced.startsWith(querySpaced) ||
              aNoSpace.startsWith(queryNoSpace)) {
            bestScore = math.max(bestScore, 75);
          } else if (aSpaced.contains(querySpaced) ||
              aNoSpace.contains(queryNoSpace)) {
            bestScore = math.max(bestScore, 50);
          }
        }

        if (bestScore > 0) {
          scored.add((bestScore, entry.city));
        }
      }
    } else {
      final queryLatin = CitySearchNormalizer.normalizeLatin(trimmed);

      for (final entry in _searchIndex) {
        int bestScore = 0;

        if (entry.normName == queryLatin || entry.normAscii == queryLatin) {
          bestScore = math.max(bestScore, 100);
        } else if (entry.normName.startsWith(queryLatin) ||
            entry.normAscii.startsWith(queryLatin)) {
          bestScore = math.max(bestScore, 75);
        } else if (entry.normName.contains(queryLatin) ||
            entry.normAscii.contains(queryLatin)) {
          bestScore = math.max(bestScore, 50);
        } else {
          // Check Latin aliases
          for (final a in entry.normLatinAliases) {
            if (a == queryLatin) {
              bestScore = math.max(bestScore, 100);
              break;
            } else if (a.startsWith(queryLatin)) {
              bestScore = math.max(bestScore, 75);
            } else if (a.contains(queryLatin)) {
              bestScore = math.max(bestScore, 50);
            }
          }
        }

        if (bestScore > 0) {
          scored.add((bestScore, entry.city));
        }
      }
    }

    // Sort by relevance score descending, then by population descending
    scored.sort((a, b) {
      final scoreCompare = b.$1.compareTo(a.$1);
      if (scoreCompare != 0) return scoreCompare;
      return b.$2.population.compareTo(a.$2.population);
    });

    final results = scored.take(limit).map((s) => s.$2).toList();
    return List.unmodifiable(results);
  }

  @override
  NearestCitySuggestion? findNearestCity(double latitude, double longitude) {
    if (!latitude.isFinite || latitude < -90.0 || latitude > 90.0) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'Latitude must be a finite number between -90 and 90 degrees',
      );
    }
    if (!longitude.isFinite || longitude < -180.0 || longitude > 180.0) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'Longitude must be a finite number between -180 and 180 degrees',
      );
    }

    if (_cities.isEmpty) return null;

    SelectedCity? closestCity;
    double minDistance = double.infinity;

    for (final city in _cities) {
      final d = _haversineDistanceKm(
        latitude,
        longitude,
        city.latitude,
        city.longitude,
      );
      if (d < minDistance) {
        minDistance = d;
        closestCity = city;
      }
    }

    if (closestCity == null) return null;
    return NearestCitySuggestion(city: closestCity, distanceKm: minDistance);
  }

  /// Computes the great-circle distance between two points in kilometers.
  static double _haversineDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final rLat1 = lat1 * math.pi / 180.0;
    final rLat2 = lat2 * math.pi / 180.0;

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rLat1) *
            math.cos(rLat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));
    return earthRadiusKm * c;
  }
}
