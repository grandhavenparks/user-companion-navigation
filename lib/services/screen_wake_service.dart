import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the display on while navigating (Android FLAG_KEEP_SCREEN_ON, set in
/// MainActivity). No extra permission or plugin is needed.
class ScreenWake {
  ScreenWake._();

  static final ScreenWake instance = ScreenWake._();

  static const MethodChannel _channel = MethodChannel('edge_forestry/screen');

  bool _keepOn = false;

  bool get isKeptOn => _keepOn;

  Future<void> setKeepOn(bool on) async {
    if (on == _keepOn) return;
    _keepOn = on;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {'on': on});
    } on PlatformException catch (e) {
      debugPrint('ScreenWake: $e');
    } on MissingPluginException catch (e) {
      debugPrint('ScreenWake: $e');
    }
  }
}
