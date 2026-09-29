# Netzon Dev Box: mobile and .NET SDKs (full image)

- Java 21 (`JAVA_HOME` set), the Android SDK in `$ANDROID_HOME` (command-line tools, platform-tools, API 36, build-tools 36.0.0; no emulator, NDK or Android Studio), Flutter stable with the Android artifacts precached, and .NET SDK 10 and 11 RC side by side in `$DOTNET_ROOT` are preinstalled.
- Without a `global.json` the newest installed .NET SDK is used; pin `global.json` in projects that need .NET 10.
- Gradle uses `/cache/gradle` and NuGet `/cache/nuget` (see the caches note).
