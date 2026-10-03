import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'config/tile_zoom_limits.dart';
import 'screens/home_screen.dart';
import 'services/map_cache_service.dart';
import 'services/tile_import_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await TileZoomCache.load();

  // Initialize map cache service
  await MapCacheService.instance.init();
  
  print('Importing offline tiles from assets (replaces fmtc/*.db)...');
  await TileImportService.instance.importTilesFromAssets();
  print('Tile import complete.');
  
  runApp(
    const ProviderScope(
      child: EdgeForestryApp(),
    ),
  );
}

class EdgeForestryApp extends StatelessWidget {
  const EdgeForestryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Edge Forestry',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
