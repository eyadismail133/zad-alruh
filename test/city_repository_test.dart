import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:zad_alruh/src/features/prayer/data/sources/city_asset_adapter.dart';
import 'package:zad_alruh/src/features/prayer/data/sources/geonames_source_verifier.dart';
import 'package:zad_alruh/src/features/prayer/domain/repositories/city_repository.dart';

class _OffsetTestAssetBundle extends Fake implements AssetBundle {
  final ByteData _byteData;
  _OffsetTestAssetBundle(this._byteData);

  @override
  Future<ByteData> load(String key) async {
    if (key == CityAssetAdapter.citiesAssetPath) {
      return _byteData;
    }
    throw ArgumentError('Unknown asset: $key');
  }
}

void main() {
  late Uint8List sourceBytes;
  late CityRepository repository;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tzdata.initializeTimeZones();
    final file = File('assets/content/cities/cities15000.txt');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'GeoNames cities15000.txt asset must exist in workspace root',
    );
    sourceBytes = file.readAsBytesSync();
    repository = CityAssetAdapter.fromBytes(sourceBytes);
  });

  group('CityAssetAdapter & GeoNamesSourceVerifier - Integrity & Loading', () {
    test('canonical SHA-256 hash matches verified source bytes exactly', () {
      expect(sourceBytes.length, 8534034);
      final verifiedContent = GeoNamesSourceVerifier.verifyBytes(sourceBytes);
      expect(verifiedContent.isNotEmpty, isTrue);
    });

    test('verifies exact canonical record count of 34,149 cities', () {
      expect(
        repository.totalCitiesCount,
        GeoNamesConstants.expectedRecordCount,
      );
      expect(repository.totalCitiesCount, 34149);
    });

    test(
      'rejects corrupted or altered bytes with GeoNamesValidationException',
      () {
        final corrupted = Uint8List.fromList(sourceBytes);
        corrupted[500] ^= 0xFF; // Flip bits
        expect(
          () => CityAssetAdapter.fromBytes(corrupted),
          throwsA(isA<GeoNamesValidationException>()),
        );
      },
    );

    test(
      'loadFromBundle parses off UI isolate via compute and respects ByteData buffer offset view',
      () async {
        const offset = 128;
        final padded = Uint8List(sourceBytes.length + offset + 64);
        padded.setRange(offset, offset + sourceBytes.length, sourceBytes);

        final offsetByteData = ByteData.view(
          padded.buffer,
          offset,
          sourceBytes.length,
        );

        final bundle = _OffsetTestAssetBundle(offsetByteData);
        final bundleRepo = await CityAssetAdapter.loadFromBundle(
          bundle: bundle,
        );
        expect(bundleRepo.totalCitiesCount, 34149);
        expect(bundleRepo.defaultCity.id, 360630);
      },
    );

    test(
      'defaultCity resolves Cairo (ID 360630) with Africa/Cairo timezone and EG country',
      () {
        final defaultCity = repository.defaultCity;
        expect(defaultCity.id, 360630);
        expect(defaultCity.name, 'Cairo');
        expect(defaultCity.countryCode, 'EG');
        expect(defaultCity.timezone, 'Africa/Cairo');
        expect(defaultCity.latitude, closeTo(30.06263, 0.001));
        expect(defaultCity.longitude, closeTo(31.24967, 0.001));
      },
    );

    test(
      'SelectedCity parsed fields are defensively immutable and validated',
      () {
        final cairo = repository.defaultCity;
        expect(
          () => cairo.aliases.add('InventedAlias'),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );
  });

  group('CityRepository - Arabic & Latin Search & Normalization', () {
    test(
      'searches Cairo in Arabic (القاهرة) and Latin (cairo) matching ID 360630',
      () {
        final arabicResults = repository.search('القاهرة');
        expect(arabicResults, isNotEmpty);
        expect(arabicResults.first.id, 360630);
        expect(arabicResults.first.name, 'Cairo');

        final latinResults = repository.search('cairo');
        expect(latinResults, isNotEmpty);
        expect(latinResults.first.id, 360630);
      },
    );

    test(
      'searches Makkah in Arabic (مكة) and Latin (mecca, makkah) matching ID 104515',
      () {
        final arabicResults = repository.search('مكة');
        expect(arabicResults, isNotEmpty);
        expect(arabicResults.first.id, 104515);

        final latinResults = repository.search('mecca');
        expect(latinResults, isNotEmpty);
        expect(latinResults.first.id, 104515);
        expect(latinResults.first.countryCode, 'SA');
      },
    );

    test(
      'searches London in Arabic (لندن) and Latin (london) matching ID 2643743',
      () {
        final arabicResults = repository.search('لندن');
        expect(arabicResults, isNotEmpty);
        expect(arabicResults.first.id, 2643743);
        expect(arabicResults.first.countryCode, 'GB');

        final latinResults = repository.search('london');
        expect(latinResults, isNotEmpty);
        expect(latinResults.first.id, 2643743);
      },
    );

    test(
      'searches New York in Arabic unspaced (نيويورك) and spaced (نيو يورك) matching ID 5128581',
      () {
        final unspacedResults = repository.search('نيويورك');
        expect(unspacedResults, isNotEmpty);
        expect(unspacedResults.first.id, 5128581);
        expect(unspacedResults.first.name, 'New York City');

        // Spaced query variant must also resolve New York City
        final spacedResults = repository.search('نيو يورك');
        expect(spacedResults, isNotEmpty);
        expect(spacedResults.first.id, 5128581);

        final latinResults = repository.search('new york');
        expect(latinResults, isNotEmpty);
        expect(latinResults.first.id, 5128581);
      },
    );

    test(
      'normalizes Arabic diacritics, Alef variants, and tatweel correctly',
      () {
        // With diacritics (tashkeel)
        final withTashkeel = repository.search('طَنطَا');
        expect(withTashkeel, isNotEmpty);
        expect(
          withTashkeel.any((c) => c.name == 'Tanta' || c.asciiName == 'Tanta'),
          isTrue,
        );

        // Alef variants: إسكندرية vs اسكندرية
        final alefVariant1 = repository.search('إسكندرية');
        final alefVariant2 = repository.search('اسكندرية');
        expect(alefVariant1, isNotEmpty);
        expect(alefVariant2, isNotEmpty);
        expect(alefVariant1.first.id, alefVariant2.first.id);
        expect(alefVariant1.first.name, 'Alexandria');

        // Tatweel: الـقـاهـرة
        final withTatweel = repository.search('الـقـاهـرة');
        expect(withTatweel, isNotEmpty);
        expect(withTatweel.first.id, 360630);
      },
    );

    test(
      'ranks exact matches before prefix matches and sorts tied scores by population descending',
      () {
        // Searching 'Tri' matches Tripoli (Libya, pop ~1.1M) and Tripoli (Lebanon, pop ~229k)
        final results = repository.search('Tripoli', limit: 10);
        expect(results.length, greaterThanOrEqualTo(2));
        // First result should have high population
        expect(results.first.population, greaterThan(results[1].population));
      },
    );

    test(
      'disambiguates identical city names across different countries and timezones',
      () {
        // 'Alexandria' exists in EG (Egypt, Africa/Cairo) and US (United States, America/New_York)
        final results = repository.search('Alexandria', limit: 20);
        final countries = results.map((c) => c.countryCode).toSet();
        expect(countries.contains('EG'), isTrue);
        expect(countries.contains('US'), isTrue);

        final egyptAlex = results.firstWhere((c) => c.countryCode == 'EG');
        expect(egyptAlex.timezone, 'Africa/Cairo');
        expect(egyptAlex.population, greaterThan(3000000));
      },
    );
  });

  group('CityRepository - Geodesic Nearest City Approximation', () {
    test('finds Cairo as nearest city for coordinates near central Cairo', () {
      // Approximate coordinates near Giza / central Cairo
      final suggestion = repository.findNearestCity(30.05, 31.25);
      expect(suggestion, isNotNull);
      expect(suggestion!.city.id, 360630);
      expect(suggestion.distanceKm, lessThan(10.0));
    });

    test('finds London as nearest city for central London coordinates', () {
      final suggestion = repository.findNearestCity(51.5074, -0.1278);
      expect(suggestion, isNotNull);
      expect(suggestion!.city.id, 2643743);
      expect(suggestion.distanceKm, lessThan(5.0));
    });

    test('finds New York City as nearest city for Manhattan coordinates', () {
      final suggestion = repository.findNearestCity(40.7128, -74.0060);
      expect(suggestion, isNotNull);
      expect(suggestion!.city.id, 5128581);
      expect(suggestion.distanceKm, lessThan(5.0));
    });

    test('finds Mecca as nearest city for Haram coordinates', () {
      final suggestion = repository.findNearestCity(21.4225, 39.8262);
      expect(suggestion, isNotNull);
      expect(suggestion!.city.id, 104515);
      expect(suggestion.distanceKm, lessThan(5.0));
    });

    test('throws ArgumentError on invalid latitude or longitude', () {
      expect(
        () => repository.findNearestCity(95.0, 31.0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => repository.findNearestCity(-95.0, 31.0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => repository.findNearestCity(30.0, 185.0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => repository.findNearestCity(double.nan, 31.0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => repository.findNearestCity(30.0, double.infinity),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CityRepository - Input Validation & Edge Cases', () {
    test('search rejects non-positive limit with ArgumentError', () {
      expect(
        () => repository.search('Cairo', limit: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => repository.search('Cairo', limit: -5),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('search returns empty list for whitespace-only query', () {
      expect(repository.search(''), isEmpty);
      expect(repository.search('   '), isEmpty);
      expect(repository.search('\t\n'), isEmpty);
    });

    test('getCityById returns null for nonexistent ID', () {
      expect(repository.getCityById(-1), isNull);
      expect(repository.getCityById(999999999), isNull);
    });

    test('getCityById retrieves canonical Cairo and London records', () {
      final cairo = repository.getCityById(360630);
      expect(cairo, isNotNull);
      expect(cairo!.name, 'Cairo');

      final london = repository.getCityById(2643743);
      expect(london, isNotNull);
      expect(london!.name, 'London');
    });
  });
}
