import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useFeet = false;
  int _gpsIntervalSeconds = AppConfig.defaultGpsUpdateIntervalSeconds;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useFeet = prefs.getBool('use_feet') ?? false;
      _gpsIntervalSeconds =
          prefs.getInt('gps_interval_seconds') ?? AppConfig.defaultGpsUpdateIntervalSeconds;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_feet', _useFeet);
    await prefs.setInt('gps_interval_seconds', _gpsIntervalSeconds);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Distance in feet'),
            subtitle: const Text('Otherwise meters'),
            value: _useFeet,
            onChanged: (v) {
              setState(() => _useFeet = v);
              _save();
            },
          ),
          ListTile(
            title: const Text('GPS update interval'),
            subtitle: Text('$_gpsIntervalSeconds seconds'),
          ),
          const Divider(),
          ListTile(
            title: const Text('About'),
            subtitle: Text('${AppConfig.appName} v${AppConfig.appVersion}'),
          ),
        ],
      ),
    );
  }
}
