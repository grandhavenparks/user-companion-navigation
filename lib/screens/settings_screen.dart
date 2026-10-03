import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/map_config.dart';
import '../providers/basemap_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final basemap = ref.watch(basemapProvider).valueOrNull;
    final manifest = basemap?.manifest;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Distances in feet'),
            subtitle: const Text('Otherwise metres'),
            value: settings.useFeet,
            onChanged: notifier.setUseFeet,
          ),
          ListTile(
            title: const Text('GPS update interval'),
            subtitle: const Text('Shorter is smoother, longer saves battery'),
            trailing: DropdownButton<int>(
              value: settings.gpsIntervalSeconds,
              underline: const SizedBox.shrink(),
              items: [
                for (final s in AppConfig.gpsIntervalChoices)
                  DropdownMenuItem(value: s, child: Text('$s s')),
              ],
              onChanged: (v) {
                if (v != null) notifier.setGpsIntervalSeconds(v);
              },
            ),
          ),
          ListTile(
            title: const Text('Arrival radius'),
            subtitle: const Text('Distance at which "Mark visited" is offered'),
            trailing: DropdownButton<double>(
              value: settings.arrivalRadiusMeters,
              underline: const SizedBox.shrink(),
              items: [
                for (final r in AppConfig.arrivalRadiusChoices)
                  DropdownMenuItem(value: r, child: Text('${r.round()} m')),
              ],
              onChanged: (v) {
                if (v != null) notifier.setArrivalRadiusMeters(v);
              },
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Offline map'),
            subtitle: Text(manifest == null
                ? (basemap?.message ?? 'Not loaded yet')
                : [
                    if (manifest.parkNames.isNotEmpty)
                      'Parks: ${manifest.parkNames.join(', ')}',
                    if (manifest.createdUtc != null)
                      'Built: ${manifest.createdUtc!.toLocal()}',
                    'Data zoom ${manifest.minZoom}-${manifest.maxZoom}, '
                        'shown up to ${MapConfig.maxZoom.round()}',
                    if (manifest.bufferMeters != null)
                      'Margin around parks: ${manifest.bufferMeters!.round()} m',
                    if (manifest.source != null) 'Source: ${manifest.source}',
                  ].join('\n')),
            isThreeLine: manifest != null,
          ),
          const ListTile(
            title: Text('Map data'),
            subtitle: Text(MapConfig.attribution),
          ),
          const Divider(),
          const ListTile(
            title: Text('About'),
            subtitle: Text('${AppConfig.appName} v${AppConfig.appVersion}'),
          ),
        ],
      ),
    );
  }
}
