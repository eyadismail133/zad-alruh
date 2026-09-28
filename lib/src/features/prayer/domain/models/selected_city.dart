import 'package:adhan/adhan.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Immutable domain model representing a validated city from the GeoNames cities15000 dataset.
class SelectedCity {
  final int id;
  final String name;
  final String asciiName;
  final String? arabicName;
  final String countryCode;
  final double latitude;
  final double longitude;
  final String timezone;
  final int population;
  final List<String> aliases;

  static bool _timeZonesInitialized = false;

  static void _ensureTimeZones() {
    if (!_timeZonesInitialized) {
      tzdata.initializeTimeZones();
      _timeZonesInitialized = true;
    }
  }

  /// Public constructor enforcing comprehensive runtime validation on all inputs.
  SelectedCity({
    required this.id,
    required this.name,
    required this.asciiName,
    this.arabicName,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.population,
    List<String> aliases = const [],
  }) : aliases = List.unmodifiable(aliases) {
    if (id <= 0) {
      throw ArgumentError.value(id, 'id', 'City id must be a positive integer');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'City name cannot be empty');
    }
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
    if (countryCode.trim().length != 2) {
      throw ArgumentError.value(
        countryCode,
        'countryCode',
        'Country code must be exactly 2 characters',
      );
    }
    if (population < 0) {
      throw ArgumentError.value(
        population,
        'population',
        'Population cannot be negative',
      );
    }
    _ensureTimeZones();
    try {
      tz.getLocation(timezone);
    } catch (_) {
      throw ArgumentError.value(
        timezone,
        'timezone',
        'Unknown or unsupported IANA timezone',
      );
    }
  }

  /// Internal constructor for compile-time verified canonical constants.
  const SelectedCity._trusted({
    required this.id,
    required this.name,
    required this.asciiName,
    this.arabicName,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.population,
    this.aliases = const [],
  });

  /// Canonical default city: Cairo, Egypt (GeoNames ID 360630).
  static const SelectedCity cairo = SelectedCity._trusted(
    id: 360630,
    name: 'Cairo',
    asciiName: 'Cairo',
    arabicName: 'القاهرة',
    countryCode: 'EG',
    latitude: 30.06263,
    longitude: 31.24967,
    timezone: 'Africa/Cairo',
    population: 9606916,
    aliases: ['القاهرة', 'قاهره', 'Masr', 'Misr'],
  );

  /// Canonical reference city: London, United Kingdom (GeoNames ID 2643743).
  static const SelectedCity london = SelectedCity._trusted(
    id: 2643743,
    name: 'London',
    asciiName: 'London',
    arabicName: 'لندن',
    countryCode: 'GB',
    latitude: 51.50853,
    longitude: -0.12574,
    timezone: 'Europe/London',
    population: 8961989,
    aliases: ['لندن'],
  );

  /// Canonical reference city: New York City, United States (GeoNames ID 5128581).
  static const SelectedCity newYork = SelectedCity._trusted(
    id: 5128581,
    name: 'New York City',
    asciiName: 'New York City',
    arabicName: 'نيويورك',
    countryCode: 'US',
    latitude: 40.71427,
    longitude: -74.00597,
    timezone: 'America/New_York',
    population: 8804190,
    aliases: ['نيويورك'],
  );

  /// Canonical reference city: Makkah, Saudi Arabia (GeoNames ID 104515).
  static const SelectedCity makkah = SelectedCity._trusted(
    id: 104515,
    name: 'Makkah',
    asciiName: 'Makkah',
    arabicName: 'مكة المكرمة',
    countryCode: 'SA',
    latitude: 21.42664,
    longitude: 39.82563,
    timezone: 'Asia/Riyadh',
    population: 1578722,
    aliases: ['مكة', 'مكة المكرمة', 'مكه', 'Mecca'],
  );

  /// Determines default calculation method based on country of the city:
  /// Egypt uses Egyptian General Authority of Survey; other countries default to Muslim World League.
  CalculationMethod get defaultCalculationMethod {
    if (countryCode.toUpperCase() == 'EG') {
      return CalculationMethod.egyptian;
    }
    return CalculationMethod.muslim_world_league;
  }

  SelectedCity copyWith({
    int? id,
    String? name,
    String? asciiName,
    String? arabicName,
    String? countryCode,
    double? latitude,
    double? longitude,
    String? timezone,
    int? population,
    List<String>? aliases,
  }) {
    return SelectedCity(
      id: id ?? this.id,
      name: name ?? this.name,
      asciiName: asciiName ?? this.asciiName,
      arabicName: arabicName ?? this.arabicName,
      countryCode: countryCode ?? this.countryCode,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timezone: timezone ?? this.timezone,
      population: population ?? this.population,
      aliases: aliases ?? this.aliases,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SelectedCity &&
        other.id == id &&
        other.name == name &&
        other.asciiName == asciiName &&
        other.arabicName == arabicName &&
        other.countryCode == countryCode &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.timezone == timezone &&
        other.population == population;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    asciiName,
    arabicName,
    countryCode,
    latitude,
    longitude,
    timezone,
    population,
  );

  @override
  String toString() =>
      'SelectedCity(id: $id, name: $name, arabic: $arabicName, country: $countryCode, zone: $timezone, pop: $population)';
}
