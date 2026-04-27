# Android build notes

Values below match the committed Gradle files; re-run `flutter doctor` and open the project in Android Studio if builds fail after SDK updates.

| Component | Version / setting |
|-----------|-------------------|
| Android Gradle Plugin | `8.3.2` (`android/settings.gradle`) |
| Kotlin | `1.9.24` |
| Gradle wrapper | `8.4` (`gradle-wrapper.properties`) |
| Java | `17` (`compileOptions` / `kotlinOptions` in `android/app/build.gradle`) |
| NDK | `25.1.8937393` (required by some native dependencies — install via Android SDK Manager if the build asks for it) |

The application id / namespace in `android/app/build.gradle` is still the default `com.example.usercompanionnavigation` unless you change it for release.
