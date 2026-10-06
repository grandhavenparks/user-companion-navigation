/// Application-wide configuration constants.
class AppConfig {
  AppConfig._();

  static const String appName = 'User Navigation Companion';
  static const String appVersion = '1.3.3';

  /// SQLite database for datasets, points and visit state.
  static const String databaseName = 'user_navigation_companion.db';
  static const int databaseVersion = 3;

  // --- GPS -----------------------------------------------------------------

  /// Default GPS update interval in seconds (1 s gives the smoothest marker).
  static const int defaultGpsIntervalSeconds = 1;
  static const List<int> gpsIntervalChoices = [1, 2, 5, 10];

  /// Below this speed (m/s) the GPS course is unreliable and is not shown.
  static const double minSpeedForHeading = 0.7;

  /// A jump larger than this (metres) is drawn instantly instead of animated,
  /// e.g. the first fix after the screen was off for a while.
  static const double snapDistanceMeters = 250;

  // --- Navigation ----------------------------------------------------------

  /// Distance at which a point counts as "arrived".
  static const double defaultArrivalRadiusMeters = 10;
  static const List<double> arrivalRadiusChoices = [5, 10, 15, 20, 30];

  /// "Arrived" distance for clusters (a cluster covers a 100 m cell).
  static const double defaultClusterArrivalRadiusMeters = 25;
  static const List<double> clusterArrivalRadiusChoices = [10, 15, 20, 25, 30, 40, 50];

  // --- Clusters ------------------------------------------------------------

  /// Grid cell size used to merge nearby points (same as the old app).
  static const double clusterCellMeters = 100;

  /// When the user wanders off, a different point becomes the target once it
  /// is closer than the current target by at least
  /// max([targetSwitchMinMeters], [targetSwitchFraction] x current distance,
  /// half the GPS accuracy). This keeps the target from flickering between
  /// two nearly equidistant points.
  static const double targetSwitchMinMeters = 5;
  static const double targetSwitchFraction = 0.2;

  /// Route ordering uses nearest-neighbour plus 2-opt refinement; above this
  /// many points the refinement is skipped to keep the UI responsive.
  static const int maxPointsForRouteRefinement = 600;
}
