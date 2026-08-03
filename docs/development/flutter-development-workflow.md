# Flutter Development Workflow

## Prerequisites

Install a compatible Flutter SDK, Android SDK, and a physical device or emulator. Enable USB debugging when using a physical device.

## Local Development

Run the application from `apps/mobile-flutter/`:

```powershell
flutter pub get
flutter devices
flutter run -d <device-id>
```

Use hot reload for Dart UI changes. Restart the application after changing dependencies, Android manifest entries, Gradle configuration, native platform code, or application bootstrap logic.

## Network Considerations

When testing a VPN client, ensure that the local development machine retains a route to the Android device and required development services. Do not commit local routing scripts, device identifiers, host paths, or endpoint-specific workarounds.

## Verification

Run static analysis and relevant tests before opening a pull request:

```powershell
flutter analyze
flutter test ../../qa/tests
```
