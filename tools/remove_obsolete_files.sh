#!/usr/bin/env bash
# Removes files the app no longer uses. Safe to run more than once:
#   bash tools/remove_obsolete_files.sh
set -euo pipefail
cd "$(dirname "$0")/.."

obsolete=(
  download_tiles.py
  assets/tiles
  lib/config/tile_zoom_limits.dart
  lib/providers/tile_zoom_limits_provider.dart
  lib/providers/visit_provider.dart
  lib/providers/visit_repository_provider.dart
  lib/repositories/visit_repository.dart
  lib/models/visit_record.dart
  lib/services/geojson_parser_service.dart
  lib/services/map_cache_service.dart
  lib/services/offline_tile_provider.dart
  lib/services/tile_import_service.dart
  lib/services/points_service.dart
  lib/services/park_route_service.dart
  lib/utils/geojson_validator.dart
  lib/utils/permissions_handler.dart
  lib/widgets/map_layer_selector.dart
  test/widget_test.dart
  # 1.2: Kotlin package moved to com/user_navigation_companion
  android/app/src/main/kotlin/com/example
)

for path in "${obsolete[@]}"; do
  if [ -e "$path" ]; then
    rm -rf -- "$path"
    echo "removed  $path"
  fi
done
echo "Done."
