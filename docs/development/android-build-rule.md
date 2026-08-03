# Android Build Guidance

Use incremental workflows for normal Dart and UI work. Run the application through Flutter and select a connected device or emulator:

```powershell
cd apps/mobile-flutter
flutter run -d <device-id>
```

Use hot reload for normal UI changes and hot restart after application bootstrap changes.

Build an installable release package only when a device test requires it. Release endpoints and `--dart-define` values are environment-specific and must be supplied outside source control.

Run a full rebuild after dependency, Gradle, native Android, or asset-pipeline changes.
