import '../models/nearest_city_suggestion.dart';
import '../models/selected_city.dart';

/// Pure Dart contract for querying offline GeoNames world cities.
abstract class CityRepository {
  /// Searches for cities matching the given query text.
  ///
  /// Supports:
  /// - Arabic alias searches with diacritic and space normalization (e.g. 'القاهرة', 'مكة', 'نيو يورك').
  /// - Latin name and ASCII searches (case-insensitive).
  /// - Disambiguation by country code and population order.
  List<SelectedCity> search(String query, {int limit = 50});

  /// Retrieves a specific city by its unique GeoNames ID.
  SelectedCity? getCityById(int id);

  /// Suggests the nearest city to given coordinates using geodesic great-circle distance.
  /// Note: this is an approximate suggestion, not timezone boundary polygon resolution.
  NearestCitySuggestion? findNearestCity(double latitude, double longitude);

  /// The standard default city (Cairo, Egypt).
  SelectedCity get defaultCity;

  /// Returns the total number of validated cities available in the repository.
  int get totalCitiesCount;
}
