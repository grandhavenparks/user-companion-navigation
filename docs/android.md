# Android build notes

Values match the Flutter 3.41 project templates.

| Component | Version / setting |
|-----------|-------------------|
| Android Gradle Plugin | 8.11.1 (`android/settings.gradle`) |
| Kotlin | 2.2.20 |
| Gradle wrapper | 8.14 |
| Java | 17 (`JAVA_HOME` = Corretto 17) |
| NDK | `flutter.ndkVersion` (28.2.13676358) |
| compile/target SDK | `flutter.compileSdkVersion` / `flutter.targetSdkVersion` (36) |
| min SDK | `flutter.minSdkVersion` (24) |

## Device (Pixel 4, Android 13)

```bash
# Remove older builds that used other package ids (wipes their data).
# "DELETE_FAILED_INTERNAL_ERROR" just means that package is not installed.
adb uninstall com.edgeforestry
adb uninstall com.example.edge_forestry_mobile

# Install / update this app
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Start fresh (wipes datasets and visited marks of this app)
adb uninstall com.user_navigation_companion
```

- App name: **User Navigation Companion** (`android:label`).
- Application id and namespace: `com.user_navigation_companion`;
  `MainActivity.kt` lives in `android/app/src/main/kotlin/com/user_navigation_companion/`.
- Release builds are signed with this Mac's debug keystore
  (`~/.android/debug.keystore`). An APK built on another machine cannot be
  installed over this one without uninstalling (which deletes app data).
- Permissions: fine + coarse location only. Grant **precise** location; the
  map shows a warning when only approximate location is allowed.
- The screen is kept on while navigating via `FLAG_KEEP_SCREEN_ON`
  (`MainActivity.kt`, channel `edge_forestry/screen`).
