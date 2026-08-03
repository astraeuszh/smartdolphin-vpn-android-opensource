# Smart Dolphin VPN Android

Smart Dolphin VPN Android is an Android VPN client built with Flutter and native Android integrations.

## Repository layout

- `apps/mobile-flutter/`: Flutter application
- `platforms/android/`: Android host application and VPN integration
- `packages/security/`: security-related package code
- `qa/tests/`: automated tests

## Getting started

Install a compatible Flutter SDK, then run the Flutter commands from `apps/mobile-flutter/`. Android-specific project files live in `platforms/android/`.

## Open-source preparation

Run `scripts/audit-open-source.ps1` before publishing a release or pushing the repository to a new remote. It reports likely credentials, private keys, public endpoints, and project-specific identifiers for review.

## Documentation

- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Contributors](CONTRIBUTORS.md)
- [Acknowledgments](ACKNOWLEDGMENTS.md)

No license has been selected for this repository yet. Do not assume redistribution rights until a license is added.
