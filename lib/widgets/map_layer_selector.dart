import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../config/map_config.dart';
import '../config/tile_zoom_limits.dart';

enum MapLayerType { osm, topo }

class MapLayerSelector extends StatelessWidget {
  const MapLayerSelector({
    super.key,
    required this.currentLayer,
    required this.onLayerChanged,
  });

  final MapLayerType currentLayer;
  final ValueChanged<MapLayerType> onLayerChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LayerChip(
              label: 'Street',
              selected: currentLayer == MapLayerType.osm,
              onTap: () => onLayerChanged(MapLayerType.osm),
            ),
            const SizedBox(width: 8),
            _LayerChip(
              label: 'Topo',
              selected: currentLayer == MapLayerType.topo,
              onTap: () => onLayerChanged(MapLayerType.topo),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayerChip extends StatelessWidget {
  const _LayerChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

TileLayer tileLayerForType(MapLayerType type, TileZoomLimits limits) {
  switch (type) {
    case MapLayerType.osm:
      return MapConfig.osmTileLayer(limits);
    case MapLayerType.topo:
      return MapConfig.openTopoMapLayer(limits);
  }
}

double maxZoomForLayerType(MapLayerType type, TileZoomLimits limits) {
  switch (type) {
    case MapLayerType.osm:
      return limits.maxZoomOsm.toDouble();
    case MapLayerType.topo:
      return limits.maxZoomTopo.toDouble();
  }
}
