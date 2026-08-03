# Contributing

## Before you start

Open an issue before proposing a large feature or an incompatible behavior change. Keep each pull request focused and include tests when behavior changes.

## Development standards

- Do not commit generated build output, credentials, production endpoints, signing files, user data, or release artifacts.
- Keep deployment configuration outside the repository. Test fixtures must use non-production values.
- Follow the existing Dart, Kotlin, and Rust formatting conventions.
- Update public documentation whenever a public interface, configuration contract, or workflow changes.

## Verification

Before opening a pull request, run the relevant checks from `apps/mobile-flutter/`:

```powershell
flutter analyze
flutter test ../../qa/tests
```

Run `scripts/audit-open-source.ps1` when a change touches configuration, networking, logging, release tooling, or authentication.

## Contributor License

By submitting a contribution, you agree that it may be distributed under the Apache License 2.0.
