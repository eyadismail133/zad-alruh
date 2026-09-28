import 'selected_city.dart';

/// Represents a suggestion for the nearest city to given geographical coordinates,
/// computed via geodesic great-circle distance.
class NearestCitySuggestion {
  final SelectedCity city;
  final double distanceKm;

  const NearestCitySuggestion({required this.city, required this.distanceKm});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NearestCitySuggestion &&
        other.city == city &&
        (other.distanceKm - distanceKm).abs() < 1e-4;
  }

  @override
  int get hashCode => Object.hash(city, distanceKm.round());

  @override
  String toString() =>
      'NearestCitySuggestion(city: ${city.name}, distance: ${distanceKm.toStringAsFixed(1)} km)';
}
