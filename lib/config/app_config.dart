/// Application-wide configuration constants.
class AppConfig {
  AppConfig._();

  static const String appName = 'User Companion Navigation App';
  static const String appVersion = '1.0.0';

  /// Default GPS update interval in seconds.
  static const int defaultGpsUpdateIntervalSeconds = 5;

  /// Distance in meters within which user is considered "arrived" at tree.
  static const double arrivedThresholdMeters = 10.0;

  /// Default map zoom level when centering on user.
  static const double defaultMapZoom = 15.0;

  /// Minimum zoom level for map.
  static const double minMapZoom = 3.0;

  /// Maximum zoom level for map.
  static const double maxMapZoom = 19.0;

  /// Database name for SQLite.
  static const String databaseName = 'user_companion_navigation_app.db';
  static const int databaseVersion = 2; // Incremented for visit_notes field
}
