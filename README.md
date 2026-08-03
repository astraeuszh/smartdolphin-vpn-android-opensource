# Smart Dolphin VPN Android

Smart Dolphin VPN Android is an Android VPN client built with Flutter, Kotlin, and a native VPN service integration.

Deployment-specific endpoints, credentials, signing material, and node configuration are intentionally excluded. The repository contains safe placeholder values so contributors can provide their own development configuration.

## Repository layout

- `apps/mobile-flutter/`: Flutter application
- `platforms/android/`: Android host application and VPN integration
- `packages/security/`: security-related package code
- `qa/tests/`: automated tests

## Development

Install a compatible Flutter SDK, then run the following commands from `apps/mobile-flutter/`:

```powershell
flutter pub get
flutter analyze
flutter test ../../qa/tests
```

Android-specific project files live in `platforms/android/`. Refer to [the development workflow](docs/development/flutter-development-workflow.md) before working with a physical device.

## Open-source preparation

Run `scripts/audit-open-source.ps1` before publishing a release or pushing the repository to a new remote. It reports likely credentials, private keys, public endpoints, and project-specific identifiers for review.

## Documentation

- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Contributors](CONTRIBUTORS.md)
- [Acknowledgments](ACKNOWLEDGMENTS.md)
- [Architecture](docs/architecture/FRAMEWORK_ANDROID.md)
- [Security specification](docs/SECURITY_RUST_SPEC.md)

This repository is licensed under the [Apache License 2.0](LICENSE).
