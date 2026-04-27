import 'package:permission_handler/permission_handler.dart';

/// Request location permission (required for navigation).
Future<bool> requestLocationPermission() async {
  final status = await Permission.location.request();
  return status.isGranted;
}

/// Check if location permission is granted.
Future<bool> hasLocationPermission() async {
  return await Permission.location.isGranted;
}

/// Request storage permission (for file import on older Android).
Future<bool> requestStoragePermission() async {
  if (await Permission.storage.isGranted) return true;
  if (await Permission.manageExternalStorage.isGranted) return true;
  final status = await Permission.storage.request();
  return status.isGranted;
}

/// Open app settings so user can grant permissions manually.
Future<void> openAppSettingsAsync() => openAppSettings();
